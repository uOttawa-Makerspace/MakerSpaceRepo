# frozen_string_literal: true

module Payments
  class ShopifyAdapter
    # The gid-level Shopify draft order calls (a draft order id, no record): fetch, create, delete and the listing of
    # payable drafts. They check nothing about whose draft it is: the models reach them only through their own rules
    # (ShopifyConcern's record bookkeeping, JobOrder::DraftDeletion, LockerRental, the sweeps), never as model methods.
    module DraftOrders
      # Shopify did not answer a draft check that must be answered (#fetch_or_raise).
      class Unanswered < StandardError; end

      GET_QUERY = <<~QUERY
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

      CREATE_QUERY = <<~QUERY
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

      DELETE_QUERY = <<~QUERY
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

      LIST_QUERY = <<~GRAPHQL
        query shopifyOpenDrafts($query: String!, $first: Int!, $after: String) {
          draftOrders(first: $first, after: $after, query: $query) {
            nodes {
              id
              status
              tags
              createdAt
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      GRAPHQL

      # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
      # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
      # propagate (unknown, never "gone").
      def self.fetch_result(gid)
        answer = Answer.new(ShopifyAdapter.admin_client.query(query: GET_QUERY, variables: { id: gid }))
        return [:error, nil] unless answer.ok?

        # Not Answer#data: a 200 whose body is not a JSON object raises here (pinned), rather than reading as :error.
        draft = answer.body&.dig("data", "draftOrder")
        return [:found, draft] unless draft.nil?

        data = answer.clean_data
        [data.is_a?(Hash) && data.key?("draftOrder") ? :gone : :error, nil]
      end

      # [:found | :gone, draft]; Shopify not answering raises Unanswered.
      def self.fetch_or_raise(gid)
        state, draft = fetch_result(gid)
        raise Unanswered, "Shopify did not answer the draft order check" if state == :error

        [state, draft]
      end

      # draftOrderCreate with `variables` ({ input: DraftOrderInput }). Returns [the draft's gid, its invoice URL] and
      # stores nothing. Raises on anything but HTTP 200, on userErrors, and on an answer without the draft.
      def self.create(variables)
        resp = ShopifyAdapter.admin_client.query(query: CREATE_QUERY, variables: variables)
        raise "Network error: Received HTTP #{resp.code} while creating draft order" unless resp.code == 200

        user_errors = resp.body&.dig("data", "draftOrderCreate", "userErrors")
        raise "Shopify Draft Order Creation Failed: #{user_errors.map { |e| e['message'] }.join(', ')}" if user_errors.present?

        draft_order_data = resp.body&.dig("data", "draftOrderCreate", "draftOrder")
        raise "No draft order data received: #{resp.body}" unless draft_order_data

        [draft_order_data["id"], draft_order_data["invoiceUrl"]]
      end

      # draftOrderDelete for the draft `gid`. Its only caller is DraftRemoval (the one delete-and-classify rule).
      # `user_errors_out`: optional Array that receives Shopify's userErrors.
      # True when Shopify reports it deleted the draft. Fail closed: anything but HTTP 200 raises.
      def self.delete(gid, user_errors_out: nil)
        resp = ShopifyAdapter.admin_client.query(query: DELETE_QUERY, variables: { input: { id: gid } })
        raise "Received HTTP #{resp.code} when deleting shopify draft order" unless resp.code == 200

        user_errors_out&.concat(Array(resp.body&.dig("data", "draftOrderDelete", "userErrors")))
        resp.body&.dig("data", "draftOrderDelete", "deletedId").present?
      end

      # The search that lists the payable (DraftStatus::PAYABLE) drafts carrying `tag`.
      def self.payable_search(tag)
        "(#{DraftStatus::PAYABLE.map { |s| "status:#{s.downcase}" }.join(' OR ')}) tag:#{tag}"
      end

      # One page of the payable drafts carrying `tag`, after the cursor `after` (nil: the first page): the
      # "draftOrders" object, with its "nodes" and "pageInfo". Raises when Shopify does not answer with one.
      def self.payable_page(tag:, first:, after:)
        answer = Answer.new(ShopifyAdapter.admin_client.query(
                              query: LIST_QUERY, variables: { query: payable_search(tag), first: first, after: after }
                            ))
        raise "Received HTTP #{answer.code} when listing draft orders" unless answer.ok?
        raise "Shopify errors listing draft orders: #{answer.body['errors']}" if answer.errors?

        page = answer.data("draftOrders")
        raise "No draftOrders in the answer" unless page.is_a?(Hash) && page["nodes"].is_a?(Array) && page["pageInfo"].is_a?(Hash)

        page
      end
    end
  end
end
