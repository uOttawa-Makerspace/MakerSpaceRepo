# frozen_string_literal: true

module ShopifyConcern
  extend ActiveSupport::Concern

  # Shopify answered a metafield lookup with an error (a non-200 status, or GraphQL `errors` at any status, e.g.
  # THROTTLED or INTERNAL_SERVER_ERROR). Transient: the lookup is retried later, never read as "no metafields".
  class MetafieldLookupFailed < StandardError; end

  # Shopify refused the metafield lookup in a way a retry cannot change (an access or invalid-id error): the
  # caller treats the order as having no metafields and reports it. `codes` are Shopify's error codes only.
  class MetafieldLookupRejected < StandardError
    attr_reader :codes

    def initialize(codes)
      @codes = codes
      super("metafield lookup rejected (#{codes.join(', ')})")
    end
  end

  # Raised by the HTTP layer or the network under a lookup; all of them are transient.
  LOOKUP_NETWORK_ERRORS = [
    ShopifyAPI::Errors::HttpResponseError, ShopifyAPI::Errors::MaxHttpRetriesExceededError, JSON::ParserError,
    Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error, EOFError, SocketError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError
  ].freeze
  TRANSIENT_GRAPHQL_CODES = %w[THROTTLED INTERNAL_SERVER_ERROR].freeze

  # Shopify kept open a draft it was asked to delete: it can still be paid.
  class DraftOrderNotDeleted < StandardError; end

  # The gid-level Shopify calls (a draft order id, no record). Deliberately not class methods of the models that
  # include the concern: they skip #ensure_can_use_draft_order, so lockers and memberships must not gain them.
  # Used by the concern's instance methods and by JobOrder (its draft rule, JobOrder::DraftSweep).
  module DraftOrders
    # THE Admin GraphQL client builder (ShopifyService.admin_client uses it too). Without a session it starts the
    # configured one; a caller that needs another store or token passes its own session.
    def self.client(session: nil)
      unless session
        ShopifyContext.start_session!
        session = ShopifyAPI::Context.active_session
      end
      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end

    # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
    # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
    # propagate (unknown, never "gone").
    def self.fetch_result(gid)
      query_draft_order = <<~QUERY
        query getDraftOrder($id: ID!) {
          draftOrder(id: $id) {
            id
            name
            invoiceUrl
            status
            tags
            lineItems(first: 1) {
              nodes {
                originalUnitPriceSet {
                  shopMoney {
                    amount
                  }
                }
              }
            }
            order {
              id
              fullyPaid
              displayFinancialStatus
            }
            metafields(first: 10) {
              nodes {
                key
                value
                type
              }
            }
          }
        }
      QUERY

      resp = client.query(query: query_draft_order, variables: { id: gid })
      return [:error, nil] unless resp.code == 200

      body = resp.body
      draft = body&.dig("data", "draftOrder")
      return [:found, draft] unless draft.nil?

      gone = body.is_a?(Hash) && body["errors"].blank? && body["data"].is_a?(Hash) && body["data"].key?("draftOrder")
      [gone ? :gone : :error, nil]
    end

    # draftOrderDelete for the draft `gid`. It checks nothing about whose draft it is, so it stays out of the models'
    # API. Its only caller is ShopifyConcern::DraftRemoval (the one delete-and-classify rule, used by
    # JobOrder::DraftDeletion and LockerRental).
    # `user_errors_out`: optional Array that receives Shopify's userErrors.
    # True when Shopify reports it deleted the draft. Fail closed: anything but HTTP 200 raises.
    def self.delete(gid, user_errors_out: nil)
      delete_draft_order = <<~QUERY
        mutation draftOrderDelete($input: DraftOrderDeleteInput!) {
          draftOrderDelete(input: $input) {
            deletedId
            userErrors {
              field
              message
            }
          }
        }
      QUERY

      resp = client.query(query: delete_draft_order, variables: { input: { id: gid } })
      raise "Received HTTP #{resp.code} when deleting shopify draft order" unless resp.code == 200

      user_errors_out&.concat(Array(resp.body&.dig("data", "draftOrderDelete", "userErrors")))
      resp.body&.dig("data", "draftOrderDelete", "deletedId").present?
    end
  end

  def self.target_tag
    Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
  end

  class_methods do
    def draft_order_processable?(tag) = draft_tag_list(tag).include?(draft_order_operating_tag)

    # A draft's tags as a list of stripped strings, whether Shopify gave an array or a comma-separated string.
    def draft_tag_list(tag)
      if tag.is_a?(String)
        tag.split(',').map(&:strip)
      elsif tag.is_a?(Array)
        tag.map(&:to_s).map(&:strip)
      else
        []
      end
    end

    def draft_order_operating_tag
      "#{ShopifyConcern.target_tag}_#{shopify_draft_order_key_name}"
    end

    def shopify_draft_order_key_name
      raise NotImplementedError, "Must define shopify_draft_order_key_name on model including ShopifyConcern"
    end

    # The marker a model's drafts carry beside the operating tag, naming the record the draft was made for
    # ("<draft_marker_name>:<id>"): what ShopifyDraftSweep reconciles by. A model that sweeps its drafts defines the name
    # and lists the marker in #shopify_draft_order_tags.
    def draft_marker_name
      raise NotImplementedError, "Must define draft_marker_name on a model whose drafts are swept"
    end

    def draft_marker_tag(record_id) = "#{draft_marker_name}:#{record_id}"

    # The record id a draft's tags name: the one marker of this model, nil when there is none or two different ones.
    def draft_marker_record_id(tags)
      pattern = /\A#{Regexp.escape(draft_marker_name)}:(\d+)\z/
      ids = draft_tag_list(tags).filter_map { |t| pattern.match(t)&.captures&.first&.to_i }.uniq
      ids.first if ids.one?
    end

    # Whether a draft with these tags is THIS environment's draft of the record `record_id` (the one rule the sweep
    # lists by and re-verifies before it deletes).
    def marked_for?(tags, record_id) = draft_order_processable?(tags) && draft_marker_record_id(tags) == record_id
  end

  def shopify_is_paid
    shopify_draft_order&.dig('order', 'fullyPaid') == true
  end

  def shopify_draft_order_key_name
    self.class.shopify_draft_order_key_name
  end

  private

  # Stores the id of a draft Shopify just created. A model that writes more in the same UPDATE overrides this
  # (JobOrder: the fingerprint of the quote the draft was built from; Membership: updated_at, checkout activity).
  def store_shopify_draft_order_id(new_id)
    update_column(:shopify_draft_order_id, new_id)
  end

  # Whether the record, read again under its row lock, may still take a new draft (#keep_draft_order_id_unless_taken).
  # A model whose drafts belong to one state overrides this.
  def may_take_draft_order? = true

  # THE step that keeps a draft Shopify has just created (`new_id`, made outside any lock) or deletes it again.
  # Under the row lock, with the row read again, the id is stored (#store_shopify_draft_order_id) only when the row
  # still has no draft and the record may still take one (#may_take_draft_order?). A draft that is not stored
  # (another request stored its draft first, the record moved on, or storing failed) is deleted on Shopify once the
  # lock is released, so a record is never left with a second payable draft; a stored draft is never deleted here.
  # Afterwards the record holds the row's draft id: this one when kept, else the winner's (or none). True when kept;
  # a failure to store re-raises after the delete.
  def keep_draft_order_id_unless_taken(new_id)
    kept = store_draft_order_id_unless_taken(new_id)
    discard_unused_draft(new_id) unless kept
    kept
  end

  def store_draft_order_id_unless_taken(new_id)
    with_lock do # reloads the row: the state and the stored draft id are read now
      next false unless shopify_draft_order_id.blank? && may_take_draft_order?

      store_shopify_draft_order_id(new_id)
      true
    end
  rescue StandardError
    # Nothing stored the id (lock timeout, deadlock, lost connection; a failed COMMIT stores nothing either): the new
    # draft would be a payable invoice no record points at.
    discard_unused_draft(new_id)
    raise
  end

  # Deletes a draft no record stores, by the shared rule (ShopifyConcern::DraftRemoval). A draft that is gone, or
  # was paid meanwhile (it became an order), needs nothing. A draft Shopify still has open, and any error asking
  # Shopify, is reported and never raised: the caller goes on with the draft the row stores.
  def discard_unused_draft(gid)
    result = ShopifyConcern::DraftRemoval.call(gid)
    return unless result.outcome == :open

    raise DraftOrderNotDeleted,
          "Shopify did not delete the unused draft order #{gid}: #{result.user_errors.map { |e| e['message'] }.join(', ')}"
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error,
                          context: { "#{self.class.model_name.singular}_id": id, step: 'delete_unused_shopify_draft_order' })
  end

  included do
    private

    def draft_order_metafields(gid = :auto)
      if gid == :auto
        ensure_can_use_draft_order
        gid = shopify_draft_order_id
      end
      return [] if gid.blank?

      query = <<~QUERY
        query NodeMetafields($ownerId: ID!) {
          node(id: $ownerId) {
            ... on Order {
              metafields(first: 50) {
                edges {
                  node {
                    namespace
                    key
                    value
                  }
                }
              }
            }
            ... on DraftOrder {
              metafields(first: 50) {
                edges {
                  node {
                    namespace
                    key
                    value
                  }
                }
              }
            }
          }
        }
      QUERY

      begin
        resp = shopify_admin_client.query(query: query, variables: { ownerId: gid })
      rescue *ShopifyConcern::LOOKUP_NETWORK_ERRORS => e
        raise ShopifyConcern::MetafieldLookupFailed, "metafield lookup failed (#{e.class})"
      end
      body = resp.body
      errors = body.is_a?(Hash) ? Array.wrap(body["errors"]) : []
      # The client raises HttpResponseError for non-2xx answers (rescued above), but it passes a 2xx that is not 200
      # (202, 204 with an empty body) through. GraphQL answers with 200, so anything else is not an answer to the
      # query; reading it as "no metafields" would send the order down the no-reference path.
      unless resp.code == 200
        raise ShopifyConcern::MetafieldLookupFailed, "metafield lookup failed (HTTP #{resp.code})"
      end
      if errors.present?
        codes = errors.filter_map { |e| e.is_a?(Hash) ? e.dig("extensions", "code").presence : nil }.uniq
        if codes.empty? || (codes & ShopifyConcern::TRANSIENT_GRAPHQL_CODES).any?
          raise ShopifyConcern::MetafieldLookupFailed, "metafield lookup failed (#{codes.join(', ').presence || 'GraphQL error'})"
        end

        raise ShopifyConcern::MetafieldLookupRejected, codes
      end

      parse_metafield_edges(body)
    end

    # [] only for a well-formed answer whose owner node is null or has no metafields (a node of another type).
    # Any other shape (no body, not a hash, no "data") is not an answer to the query: reading it as "no
    # metafields" would send a membership order down the no-reference path, so the lookup fails and is retried.
    def parse_metafield_edges(body)
      data = body.is_a?(Hash) ? body["data"] : nil
      unless data.is_a?(Hash) && data.key?("node")
        raise ShopifyConcern::MetafieldLookupFailed, "metafield lookup failed (unexpected answer)"
      end

      node = data["node"]
      return [] if node.nil? || (node.is_a?(Hash) && !node.key?("metafields"))

      edges = node.is_a?(Hash) && node["metafields"].is_a?(Hash) ? node["metafields"]["edges"] : nil
      raise ShopifyConcern::MetafieldLookupFailed, "metafield lookup failed (unexpected answer)" unless edges.is_a?(Array)

      edges.map { |edge| edge.is_a?(Hash) ? edge["node"] : nil }.compact
    end

    def shopify_admin_client
      ShopifyConcern::DraftOrders.client
    end

    def ensure_can_use_draft_order
      unless has_attribute?("shopify_draft_order_id")
        raise "Model #{self.class.name} does not define a shopify_draft_order_id column"
      end

      raise "Key name must not be blank" if shopify_draft_order_key_name.blank?

      unless respond_to?(:shopify_draft_order_line_items, true)
        raise "Line items method shopify_draft_order_line_items must be defined"
      end
    end

    def shopify_draft_order
      ensure_can_use_draft_order

      if shopify_draft_order_id.blank?
        create_shopify_draft_order
      else
        fetch_shopify_draft_order
      end
    end

    def fetch_shopify_draft_order
      fetch_shopify_draft_order_result.last
    end

    # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
    # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
    # propagate (unknown, never "gone").
    def fetch_shopify_draft_order_result(gid = shopify_draft_order_id)
      ShopifyConcern::DraftOrders.fetch_result(gid)
    end

    # Creates a draft and keeps it unless another request stored one first, then fetches the row's draft.
    def create_shopify_draft_order
      new_id, = create_remote_draft_order
      keep_draft_order_id_unless_taken(new_id)
      fetch_shopify_draft_order
    end

    # Creates the draft on Shopify and returns [its gid, the line items sent, its invoice URL]; stores nothing, so the
    # Shopify call runs outside any lock and the caller decides under the lock whether to keep the draft
    # (#keep_draft_order_id_unless_taken).
    def create_remote_draft_order
      create_draft_order = <<~QUERY
        mutation draftOrderCreate($input: DraftOrderInput!) {
          draftOrderCreate(input: $input) {
            draftOrder {
              id
              invoiceUrl
            }
            userErrors {
              field
              message
            }
          }
        }
      QUERY

      variables = shopify_draft_order_input
      resp = shopify_admin_client.query(
        query: create_draft_order,
        variables: variables
      )

      unless resp.code == 200
        raise "Network error: Received HTTP #{resp.code} while creating draft order"
      end

      user_errors = resp.body&.dig("data", "draftOrderCreate", "userErrors")
      if user_errors.present?
        messages = user_errors.map { |e| e["message"] }.join(", ")
        raise "Shopify Draft Order Creation Failed: #{messages}"
      end

      draft_order_data = resp.body&.dig("data", "draftOrderCreate", "draftOrder")
      unless draft_order_data
        raise "No draft order data received: #{resp.body}"
      end

      [draft_order_data["id"], variables.dig(:input, :lineItems), draft_order_data["invoiceUrl"]]
    end

    # The tags of the draft: the environment's operating tag (what the paid webhook routes on). A model may add
    # a marker that identifies the record the draft was made for (JobOrder: "job_order:<id>").
    def shopify_draft_order_tags
      [self.class.draft_order_operating_tag]
    end

    def shopify_draft_order_input
      {
        input: {
          note: "Generated by makerepo",
          tags: shopify_draft_order_tags,
          lineItems: send(:shopify_draft_order_line_items),
          metafields: [
            {
              namespace: "makerepo",
              key: "#{shopify_draft_order_key_name}_db_reference",
              value: id.to_s,
              type: "number_integer"
            }
          ]
        }
      }
    end
  end
end