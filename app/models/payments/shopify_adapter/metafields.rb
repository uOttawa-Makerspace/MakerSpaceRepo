# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # The metafields of a Shopify order or draft order, by its gid (ShopOrderApplier reads the makerepo references
    # from them). Raises ShopifyConcern::MetafieldLookupFailed when the lookup must be retried, and
    # ShopifyConcern::MetafieldLookupRejected when Shopify refused it for good. Those two keep their names: the class
    # name of a failure is what processed_orders.last_error records.
    module Metafields
      # Raised by the HTTP layer or the network under a lookup; all of them are transient.
      NETWORK_ERRORS = [
        ShopifyAPI::Errors::HttpResponseError, ShopifyAPI::Errors::MaxHttpRetriesExceededError, JSON::ParserError,
        Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error, EOFError, SocketError,
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, OpenSSL::SSL::SSLError
      ].freeze
      TRANSIENT_CODES = %w[THROTTLED INTERNAL_SERVER_ERROR].freeze
      # The two failures a lookup raises (see above).
      FAILED = ShopifyConcern::MetafieldLookupFailed
      REJECTED = ShopifyConcern::MetafieldLookupRejected

      QUERY = <<~QUERY
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

      module_function

      # The metafield nodes ({ "namespace", "key", "value" }) of `gid`; [] for no gid.
      def of(gid)
        return [] if gid.blank?

        answer = ask(gid)
        # The client raises HttpResponseError for non-2xx answers (rescued in #ask), but it passes a 2xx that is not 200
        # (202, 204 with an empty body) through. Reading that as "no metafields" would send the order down the
        # no-reference path.
        raise FAILED, "metafield lookup failed (HTTP #{answer.code})" unless answer.ok?

        refuse_errors!(answer.error_list)
        edges(answer.data)
      end

      def ask(gid)
        Answer.new(ShopifyAdapter.admin_client.query(query: QUERY, variables: { ownerId: gid }))
      rescue *NETWORK_ERRORS => e
        raise FAILED, "metafield lookup failed (#{e.class})"
      end

      # GraphQL errors: transient ones (or ones without a code) are retried, the others are a refusal for good.
      def refuse_errors!(errors)
        return if errors.empty?

        codes = errors.filter_map { |e| e.is_a?(Hash) ? e.dig("extensions", "code").presence : nil }.uniq
        if codes.empty? || codes.intersect?(TRANSIENT_CODES)
          raise FAILED, "metafield lookup failed (#{codes.join(', ').presence || 'GraphQL error'})"
        end

        raise REJECTED, codes
      end

      # [] only for a well-formed answer whose owner node is null or has no metafields (a node of another type).
      # Any other shape (no body, not a hash, no "data") is not an answer to the query: reading it as "no
      # metafields" would send a membership order down the no-reference path, so the lookup fails and is retried.
      def edges(data)
        raise FAILED, "metafield lookup failed (unexpected answer)" unless data.is_a?(Hash) && data.key?("node")

        node = data["node"]
        return [] if node.nil? || (node.is_a?(Hash) && !node.key?("metafields"))

        edges = node.is_a?(Hash) && node["metafields"].is_a?(Hash) ? node["metafields"]["edges"] : nil
        raise FAILED, "metafield lookup failed (unexpected answer)" unless edges.is_a?(Array)

        edges.map { |edge| edge.is_a?(Hash) ? edge["node"] : nil }.compact
      end
      private_class_method :ask, :refuse_errors!, :edges
    end
  end
end
