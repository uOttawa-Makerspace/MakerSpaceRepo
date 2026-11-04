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

  # The gid-level Shopify calls (a draft order id, no record). Deliberately not class methods of the models that
  # include the concern: they skip #ensure_can_use_draft_order, so lockers and memberships must not gain them.
  # Used by the concern's instance methods and by JobOrder (its draft rule, JobOrder::DraftSweep).
  module DraftOrders
    # THE Admin GraphQL client builder (ShopifyService.admin_client uses it too): starts the session and builds the client.
    def self.client
      ShopifyContext.start_session!
      ShopifyAPI::Clients::Graphql::Admin.new(session: ShopifyAPI::Context.active_session)
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
  end

  def shopify_is_paid
    shopify_draft_order&.dig('order', 'fullyPaid') == true
  end

  def shopify_draft_order_key_name
    self.class.shopify_draft_order_key_name
  end

  private

  # Stores the id of a draft Shopify just created from `line_items` (the exact items sent). A model that needs to
  # remember what the draft was built from overrides this (JobOrder stores a fingerprint in the same UPDATE).
  def store_shopify_draft_order_id(new_id, _line_items)
    update_column(:shopify_draft_order_id, new_id)
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

    def create_shopify_draft_order
      new_id, line_items = create_remote_draft_order
      store_shopify_draft_order_id(new_id, line_items)
      fetch_shopify_draft_order
    end

    # Creates the draft on Shopify and returns [its gid, the line items sent]; stores nothing, so a caller that must
    # decide under a lock whether to keep it (LockerRental#checkout_link) can do the Shopify call outside the lock.
    def create_remote_draft_order
      create_draft_order = <<~QUERY
        mutation draftOrderCreate($input: DraftOrderInput!) {
          draftOrderCreate(input: $input) {
            draftOrder {
              id
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

      [draft_order_data["id"], variables.dig(:input, :lineItems)]
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