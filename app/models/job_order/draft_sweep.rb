# frozen_string_literal: true

# Reclaims the Shopify drafts no job order points at.
#
# A Shopify mutation cannot be rolled back. When a database or lock error follows a draft create inside a locked
# operation, the transaction rolls back and a payable draft is left that no order row points at. Rather than
# tracking that in memory, every job-order draft carries a marker naming its order (JobOrder#shopify_draft_order_tags:
# the environment's operating tag, e.g. "makerepo_job_order", plus "job_order:<id>"), and this sweep reconciles the
# open drafts on Shopify against the database:
#
# - listed: the OPEN draft orders tagged with THIS environment's operating tag (so another environment's drafts, and
#   the locker and membership drafts, which carry other operating tags, are never listed), paginated;
# - a listed draft without exactly one valid marker (a draft made before the marker existed) is not touched;
# - kept only when the marked order exists, is live, is COMPLETED (waiting for payment) and its stored
#   shopify_draft_order_id is this draft (JobOrder#reconcile_shopify_draft!, under the order's row lock);
# - otherwise deleted, unless Shopify reports it COMPLETED (paid): that one is never deleted;
# - fail closed: any Shopify or lock error leaves the draft and lists it as unresolved.
#
# Run by `rake job_orders:sweep_orphan_drafts` and, regularly, by JobOrderDraftSweepJob (config/recurring.yml).
class JobOrder
  class DraftSweep
    PAGE_SIZE = 50
    OUTCOMES = %i[kept deleted cleared unmarked].freeze

    # counts: outcome => number; unresolved: ["<draft gid> (<reason>): <message>", ...]
    Report = Data.define(:counts, :unresolved) do
      def ok? = unresolved.empty?
    end

    LIST_QUERY = <<~GRAPHQL
      query jobOrderOpenDrafts($query: String!, $first: Int!, $after: String) {
        draftOrders(first: $first, after: $after, query: $query) {
          nodes {
            id
            status
            tags
          }
          pageInfo {
            hasNextPage
            endCursor
          }
        }
      }
    GRAPHQL

    def self.run = new.run

    def initialize
      @counts = Hash.new(0)
      @unresolved = []
    end

    def run
      list_open_drafts.each { |gid, order_id| reconcile(gid, order_id) }
      Report.new(counts: OUTCOMES.index_with { |o| @counts[o] }, unresolved: @unresolved)
    end

    private

    def operating_tag = JobOrder.draft_order_operating_tag

    # [[draft gid, order id], ...]. All pages are read before anything is deleted. A page that cannot be read ends
    # the listing and is unresolved (the next run reads it again).
    def list_open_drafts
      found = []
      cursor = nil
      loop do
        page = fetch_page(cursor)
        page["nodes"].each { |node| found << marked(node) }
        info = page["pageInfo"]
        break unless info["hasNextPage"] && info["endCursor"].present?

        cursor = info["endCursor"]
      end
      found.compact
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { where: "JobOrder::DraftSweep#list_open_drafts" })
      @unresolved << "listing open drafts (#{e.class}): #{e.message}"
      found.compact
    end

    def fetch_page(cursor)
      resp = JobOrder.shopify_admin_client.query(
        query: LIST_QUERY,
        variables: { query: "status:open tag:#{operating_tag}", first: PAGE_SIZE, after: cursor }
      )
      raise "Received HTTP #{resp.code} when listing draft orders" unless resp.code == 200

      body = resp.body
      raise "Shopify errors listing draft orders: #{body['errors']}" if body.is_a?(Hash) && body["errors"].present?

      page = body.is_a?(Hash) ? body.dig("data", "draftOrders") : nil
      raise "No draftOrders in the answer" unless page.is_a?(Hash) && page["nodes"].is_a?(Array) && page["pageInfo"].is_a?(Hash)

      page
    end

    # [gid, order id] for an OPEN draft of this environment with exactly one job-order marker, else nil (counted as
    # unmarked when it is open and this environment's but carries no usable marker). The query is only a filter:
    # what is acted on is re-checked here.
    def marked(node)
      tags = Array(node["tags"]).map { |t| t.to_s.strip }
      return nil unless node["status"] == "OPEN" && tags.include?(operating_tag)

      ids = tags.filter_map { |t| JobOrder::DRAFT_MARKER.match(t)&.captures&.first&.to_i }.uniq
      return [node["id"], ids.first] if ids.one? && node["id"].present?

      @counts[:unmarked] += 1
      nil
    end

    def reconcile(gid, order_id)
      order = JobOrder.find_by(id: order_id)
      result = order ? order.reconcile_shopify_draft!(gid) : JobOrder::TransitionResult.refused(:order_missing)
      result = delete_orphan(gid) if result.reason == :order_missing
      if result.ok?
        @counts[result.value] += 1
      else
        @unresolved << "#{gid} of job order ##{order_id} (#{result.reason}): #{result.error&.message}"
      end
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { draft_order_id: gid, job_order_id: order_id, where: "JobOrder::DraftSweep#reconcile" })
      @unresolved << "#{gid} of job order ##{order_id} (unexpected): #{e.class}: #{e.message}"
    end

    # The marked order does not exist (hard-deleted): nothing can point at the draft.
    def delete_orphan(gid)
      JobOrder::TransitionResult.done(JobOrder.delete_draft_unless_completed!(gid))
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { draft_order_id: gid, where: "JobOrder::DraftSweep#delete_orphan" })
      JobOrder::TransitionResult.refused(:draft_not_voidable, e)
    end
  end
end
