# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # One answer of the Admin GraphQL client, read the same way by every Shopify call: its HTTP status, whether it
    # carries GraphQL errors, and what it holds under "data". A body that is not a JSON object has no errors and no data.
    class Answer
      attr_reader :code, :body

      def initialize(response)
        @code = response.code
        @body = response.body
      end

      # GraphQL answers with 200; any other 2xx the client passes through (202, 204) is not an answer to the query.
      def ok? = code == 200

      def errors? = body.is_a?(Hash) && body["errors"].present?

      # The GraphQL errors as a list (a single error object is a list of one).
      def error_list = body.is_a?(Hash) ? Array.wrap(body["errors"]) : []

      # The value at `path` under "data" (all of "data" without a path).
      def data(*path) = body.is_a?(Hash) ? body.dig("data", *path) : nil

      # The value at `path` under "data" of an answer without GraphQL errors, else nil.
      def clean_data(*path) = errors? ? nil : data(*path)
    end
  end
end
