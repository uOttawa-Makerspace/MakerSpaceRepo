# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # One Shopify order payload (an orders/paid or orders/fulfilled webhook body, as received or as ProcessedOrder
    # stored it) read as a PaymentEvent. No verification here: Webhook verifies the request first.
    #
    # provider_ref is the key ProcessedOrder stores the order under (the order id; "<id>/fulfilled" for an
    # orders/fulfilled delivery), nil when the payload has no id. The references come from the order's tags: each kind
    # whose operating tag (this environment's) the order carries, its record id from the marker tag (lockers and job
    # orders; a membership's id is only in the draft's metafields, so it is nil here) and the checkout id from the
    # checkout tag; and CC Money when a line item is the CC product. An orders/fulfilled delivery is a cash payment
    # (staff fulfil a cash order without marking it paid).
    class Order
      CC_PRODUCT_ID = 4_359_597_129_784
      TAGGED_KINDS = %w[locker membership job_order].freeze
      FULFILLED = "orders/fulfilled"

      # `received_at`: when the order was received, the paid_at of an order that names no time (else the time it is
      # read).
      attr_reader :hook, :topic

      def initialize(hook, topic:, received_at: nil)
        @hook = hook
        @topic = topic
        @received_at = received_at
      end

      def event
        @event ||= PaymentEvent.new(provider: PROVIDER, provider_ref: id && ProcessedOrder.ref_for(id, @topic),
                                    references: references, amount: amount, paid_at: paid_at, cash: @topic == FULFILLED)
      end

      def id = self.class.order_id(@hook)

      # The Shopify order id: the payload's "id", else the numeric tail of its admin_graphql_api_id
      # ("gid://shopify/Order/123"), so both spellings of one order are the same key.
      def self.order_id(hook)
        hook["id"].presence&.to_s || hook["admin_graphql_api_id"].presence&.to_s&.split("/")&.last
      end

      # The line items that buy CC Money.
      def self.cc_items(hook)
        Array.wrap(hook["line_items"]).select { |i| i.is_a?(Hash) && i["product_id"].to_i == CC_PRODUCT_ID }
      end

      def self.parse_time(value)
        Time.zone.parse(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end

      private

      def references
        tags = ShopifyAdapter.tag_list(@hook["tags"])
        tagged = TAGGED_KINDS.select { |kind| tags.include?("#{ShopifyAdapter.target_tag}_#{kind}") }
                             .map { |kind| tagged_reference(kind, tags) }
        self.class.cc_items(@hook).any? ? tagged + [Reference.new(kind: "cc_money")] : tagged
      end

      def tagged_reference(kind, tags)
        Reference.new(kind: kind, record_id: MARKERS[kind] && tagged_id(tags, "#{MARKERS[kind]}:"),
                      checkout_id: tagged_id(tags, ShopifyAdapter.checkout_tag_prefix))
      end

      # The id after `prefix` in the tags: nil when no tag or two different ones carry it.
      def tagged_id(tags, prefix)
        pattern = /\A#{Regexp.escape(prefix)}(\d+)\z/
        ids = tags.filter_map { |t| pattern.match(t)&.captures&.first&.to_i }.uniq
        ids.first if ids.one?
      end

      def amount
        parsed = BigDecimal(@hook["total_price"].to_s.strip, exception: false)
        parsed.round(2) if parsed&.finite?
      end

      # orders/fulfilled: when the cash was taken (the latest fulfillment); orders/paid: the order's processed_at.
      def paid_at
        time = @topic == FULFILLED ? fulfilled_at : self.class.parse_time(@hook["processed_at"])
        time || @received_at || Time.current
      end

      def fulfilled_at
        Array(@hook["fulfillments"]).filter_map { |f| self.class.parse_time(f["created_at"]) if f.is_a?(Hash) }.max
      end
    end
  end
end
