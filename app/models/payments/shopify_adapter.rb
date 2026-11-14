# frozen_string_literal: true

module Payments
  # The Payments contract on Shopify, and the only code that talks to the Shopify SDK (with its siblings under
  # app/models/payments/; spec/config/payments_boundary_spec.rb keeps it so). A checkout is a Shopify draft order (its
  # id is the draft's gid, its pay URL the draft's invoice URL), made with the calls in DraftOrders and DraftRemoval.
  #
  #   create_checkout(lines:, reference:) -> Checkout       raises when Shopify refuses or does not answer
  #   cancel_checkout(id) -> :cancelled | :already_paid | :gone | :failed
  #   checkout_status(id) -> :open | :paid | :gone | :unknown
  #   find_open_checkout(reference:) -> Checkout or nil     the payable draft tagged with reference.checkout_id
  #   verify_webhook!(body:, headers:) -> nil               raises WebhookRejected unless the request is signed by Shopify
  #   parse_webhook(body:, headers:) -> PaymentEvent        raises WebhookRejected (see ShopifyAdapter::Webhook)
  #
  # The products that still keep their own draft id (lockers, memberships, job orders) call the Shopify-level parts
  # directly: DraftOrders (fetch, create, delete, list), DraftRemoval (the delete-and-classify rule) and Metafields.
  #
  # checkout_status answers :unknown when Shopify answers with an error (a 2xx other than 200, or GraphQL errors) or
  # with a draft in a status it does not know. cancel_checkout raises when the check after a refused delete gets no
  # answer. Both let an exception from the HTTP client or the network (a non-2xx status, a timeout) propagate: the
  # caller never reads "cancelled", "gone" or "paid" from an error.
  #
  # `lines` are Shopify DraftOrderLineItemInput hashes, passed through unchanged.
  class ShopifyAdapter
    PROVIDER = "shopify"
    # The marker tag that names the record (each model's draft_marker_name); memberships carry no marker.
    MARKERS = { "locker" => "locker_rental", "job_order" => "job_order" }.freeze
    CANCEL_OUTCOMES = { deleted: :cancelled, gone: :gone, completed: :already_paid, open: :failed }.freeze

    OPEN_CHECKOUT_QUERY = <<~GRAPHQL
      query paymentsOpenCheckout($query: String!, $first: Int!) {
        draftOrders(first: $first, query: $query, sortKey: ID) {
          nodes {
            id
            status
            tags
            invoiceUrl
          }
        }
      }
    GRAPHQL
    OPEN_CHECKOUT_PAGE = 10

    # The prefix of every tag this environment puts on its drafts (production drafts are not marked with an env).
    def self.target_tag
      Rails.env.production? ? "makerepo" : "makerepo_#{Rails.env}"
    end

    # THE Admin GraphQL client builder. Without a session it starts the configured one; a caller that needs another
    # store or token passes its own session.
    def self.admin_client(session: nil)
      unless session
        ShopifyContext.start_session!
        session = ShopifyAPI::Context.active_session
      end
      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end

    # The tag a draft made for a checkout record carries: this environment's prefix and the record's id.
    def self.checkout_tag_prefix = "#{target_tag}_checkout_"
    def self.checkout_tag(checkout_id) = "#{checkout_tag_prefix}#{checkout_id}"

    # `webhook_secrets`: the HMAC secrets webhooks are signed with; by default the configured ones, read per request.
    def initialize(webhook_secrets: nil)
      @webhook_secrets = webhook_secrets
    end

    def create_checkout(lines:, reference:)
      id, pay_url = DraftOrders.create(draft_input(lines, reference))
      Checkout.new(id: id, pay_url: pay_url)
    end

    def cancel_checkout(id) = CANCEL_OUTCOMES.fetch(DraftRemoval.call(id).outcome)

    def checkout_status(id)
      state, draft = DraftOrders.fetch_result(id)
      return :gone if state == :gone
      return :unknown unless state == :found

      draft_status(draft)
    end

    # The oldest payable draft that carries the checkout tag of reference.checkout_id. The search is only a filter:
    # the status and the tag are checked again on what Shopify returns.
    def find_open_checkout(reference:)
      raise ArgumentError, "the reference has no checkout id" if reference.checkout_id.blank?

      tag = self.class.checkout_tag(reference.checkout_id)
      node = open_drafts_tagged(tag).find { |n| open_with_tag?(n, tag) }
      node && Checkout.new(id: node["id"], pay_url: node["invoiceUrl"])
    end

    def verify_webhook!(body:, headers:) = webhook(body, headers).verify!

    def parse_webhook(body:, headers:) = webhook(body, headers).event

    private

    def webhook(body, headers) = Webhook.new(body: body, headers: headers, secrets: webhook_secrets)

    def webhook_secrets
      @webhook_secrets || [ShopifyApp.configuration.secret, ShopifyApp.configuration.old_secret]
    end

    def draft_status(draft)
      return :paid if DraftRemoval.paid?(draft)

      DraftRemoval.payable?(draft) ? :open : :unknown
    end

    # The DraftOrderInput of a checkout; Reference only holds known kinds.
    def draft_input(lines, reference)
      {
        input: {
          note: "Generated by makerepo",
          tags: draft_tags(reference),
          lineItems: lines,
          metafields: [{ namespace: "makerepo", key: "#{reference.kind}_db_reference",
                         value: reference.record_id.to_s, type: "number_integer" }]
        }
      }
    end

    # The operating tag, the record marker (lockers and job orders) and the checkout tag (when the reference has one).
    def draft_tags(reference)
      marker = MARKERS[reference.kind]
      [
        "#{self.class.target_tag}_#{reference.kind}",
        marker && "#{marker}:#{reference.record_id}",
        reference.checkout_id && self.class.checkout_tag(reference.checkout_id)
      ].compact
    end

    def open_drafts_tagged(tag)
      answer = Answer.new(self.class.admin_client.query(
                            query: OPEN_CHECKOUT_QUERY, variables: { query: DraftOrders.payable_search(tag), first: OPEN_CHECKOUT_PAGE }
                          ))
      raise "Received HTTP #{answer.code} when looking up an open checkout" unless answer.ok?

      nodes = answer.clean_data("draftOrders", "nodes")
      raise "No draftOrders in the answer to the open checkout lookup" unless nodes.is_a?(Array)

      nodes
    end

    def open_with_tag?(node, tag)
      DraftRemoval.payable?(node) && Webhook.tag_list(node["tags"]).include?(tag)
    end
  end
end
