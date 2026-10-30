# frozen_string_literal: true

# Reclaims the Shopify drafts no job order points at.
#
# A Shopify mutation cannot be rolled back. When a database or lock error follows a draft create inside a locked
# operation, the transaction rolls back and a payable draft is left that no order row points at. Rather than
# tracking that in memory, every job-order draft carries a marker naming its order (JobOrder#shopify_draft_order_tags:
# the environment's operating tag, e.g. "makerepo_job_order", plus "job_order:<id>"), and this sweep reconciles the
# unpaid drafts on Shopify against the database:
#
# - listed: the payable (JobOrder::PAYABLE_DRAFT_STATUSES: OPEN, INVOICE_SENT) draft orders tagged with THIS
#   environment's operating tag (so another environment's drafts, and the locker and membership drafts, which carry
#   other operating tags, are never listed), paginated (a repeated cursor or MAX_PAGES ends the listing, unresolved);
# - a listed draft without exactly one valid marker (a draft made before the marker existed) is not touched;
# - kept only when the database backs it (JobOrder#shopify_draft_backed?: a live order waiting for payment whose
#   stored shopify_draft_order_id is this draft);
# - otherwise deleted (JobOrder.delete_draft_unless_completed!), unless Shopify reports it paid: that one is never
#   deleted. The database is read under a short row lock; the Shopify calls are made after it is released, so a
#   slow Shopify never makes /pay or a transition answer :busy. Why that is safe: a draft the database does not
#   back at the decision can only become backed by a create that stores a NEW id (never this gid), so no later
#   write can make a deleted draft current; a draft paid in between is refused by Shopify (or seen COMPLETED);
# - at most MAX_DELETES deletes per run (a sweep run against the wrong or a restored database would otherwise
#   delete every draft): the rest is left and unresolved;
# - fail closed: any Shopify or lock error leaves the draft and lists it as unresolved;
# - one sweep at a time (a Postgres advisory lock): a second one is skipped.
#
# The Report is the one report of a run: Rails.error is told once, with the unresolved list (no per-draft reports).
# Run by `rake job_orders:sweep_orphan_drafts` and, regularly, by JobOrderDraftSweepJob (config/recurring.yml).
class JobOrder
  class DraftSweep
    PAGE_SIZE = 50
    MAX_PAGES = 1000
    MAX_DELETES = 200
    LOCK_KEY = Zlib.crc32("JobOrder::DraftSweep")
    OUTCOMES = %i[kept deleted cleared unmarked].freeze

    class Unresolved < StandardError; end

    # counts: outcome => number; unresolved: ["<draft gid> (<reason>): <message>", ...]; unresolved_gids: the drafts
    # among them; skipped: another sweep was running.
    Report = Data.define(:counts, :unresolved, :unresolved_gids, :skipped) do
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

    def self.run(max_deletes: MAX_DELETES) = new(max_deletes: max_deletes).run

    def initialize(max_deletes: MAX_DELETES)
      @max_deletes = max_deletes
      @counts = Hash.new(0)
      @unresolved = []
      @unresolved_gids = []
      @over_cap = 0
    end

    def run
      report = with_sweep_lock { sweep }
      return report if report.skipped

      report_once(report) unless report.ok?
      report
    end

    private

    def with_sweep_lock
      ActiveRecord::Base.with_connection do |conn|
        return build_report(skipped: true) unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")

        begin
          yield
        ensure
          conn.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
        end
      end
    end

    def sweep
      list_payable_drafts.each { |gid, order_id| reconcile(gid, order_id) }
      @unresolved << "#{@over_cap} orphan draft(s) not deleted: the cap of #{@max_deletes} deletes per run is reached" if @over_cap.positive?
      build_report
    end

    def build_report(skipped: false)
      Report.new(counts: OUTCOMES.index_with { |o| @counts[o] }, unresolved: @unresolved,
                 unresolved_gids: @unresolved_gids.uniq, skipped: skipped)
    end

    def report_once(report)
      Rails.error.report(Unresolved.new(report.unresolved.join("; ")), handled: true,
                         context: { unresolved_draft_order_ids: report.unresolved_gids, where: "JobOrder::DraftSweep#run" })
    end

    def operating_tag = JobOrder.draft_order_operating_tag

    def status_filter = JobOrder::PAYABLE_DRAFT_STATUSES.map { |s| "status:#{s.downcase}" }.join(" OR ")

    # [[draft gid, order id], ...], each gid once. All pages are read before anything is deleted. A page that cannot
    # be read, a repeated cursor or too many pages ends the listing and is unresolved (the next run reads it again).
    def list_payable_drafts
      found = {}
      cursors = Set.new
      cursor = nil
      MAX_PAGES.times do
        page = fetch_page(cursor)
        page["nodes"].each { |node| (pair = marked(node)) && found[pair.first] ||= pair.last }
        info = page["pageInfo"]
        return found.to_a unless info["hasNextPage"] && info["endCursor"].present?

        cursor = info["endCursor"]
        unless cursors.add?(cursor)
          @unresolved << "listing open drafts: the page cursor #{cursor.inspect} repeated, the listing is incomplete"
          return found.to_a
        end
      end
      @unresolved << "listing open drafts: more than #{MAX_PAGES} pages, the listing is incomplete"
      found.to_a
    rescue StandardError => e
      Rails.logger.error("[JobOrder::DraftSweep] listing failed: #{e.class}: #{e.message}")
      @unresolved << "listing open drafts (#{e.class}): #{e.message}"
      found.to_a
    end

    def fetch_page(cursor)
      resp = ShopifyConcern::DraftOrders.client.query(
        query: LIST_QUERY,
        variables: { query: "(#{status_filter}) tag:#{operating_tag}", first: PAGE_SIZE, after: cursor }
      )
      raise "Received HTTP #{resp.code} when listing draft orders" unless resp.code == 200

      body = resp.body
      raise "Shopify errors listing draft orders: #{body['errors']}" if body.is_a?(Hash) && body["errors"].present?

      page = body.is_a?(Hash) ? body.dig("data", "draftOrders") : nil
      raise "No draftOrders in the answer" unless page.is_a?(Hash) && page["nodes"].is_a?(Array) && page["pageInfo"].is_a?(Hash)

      page
    end

    # [gid, order id] for a payable draft of this environment with exactly one job-order marker, else nil (counted as
    # unmarked when it is payable and this environment's but carries no usable marker). The query is only a filter:
    # what is acted on is re-checked here.
    def marked(node)
      tags = Array(node["tags"]).map { |t| t.to_s.strip }
      return nil unless JobOrder::PAYABLE_DRAFT_STATUSES.include?(node["status"]) && tags.include?(operating_tag)

      ids = tags.filter_map { |t| JobOrder::DRAFT_MARKER.match(t)&.captures&.first&.to_i }.uniq
      return [node["id"], ids.first] if ids.one? && node["id"].present?

      @counts[:unmarked] += 1
      nil
    end

    def reconcile(gid, order_id)
      order = JobOrder.find_by(id: order_id)
      backed = order ? order.shopify_draft_backed?(gid) : JobOrder::TransitionResult.refused(:order_missing)
      return count(:kept) if backed.ok? && backed.value
      return unresolve(gid, order_id, backed.reason, backed.error) unless backed.ok? || backed.reason == :order_missing

      return @over_cap += 1 if @counts[:deleted] >= @max_deletes

      delete_orphan(gid, order_id, order)
    rescue StandardError => e
      Rails.logger.error("[JobOrder::DraftSweep] #{gid}: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      unresolve(gid, order_id, :unexpected, e)
    end

    # Outside any lock. Then the order, if it still stores this id, drops it (a kept draft keeps its id).
    def delete_orphan(gid, order_id, order)
      outcome = JobOrder.delete_draft_unless_completed!(gid)
      if order && outcome != :kept
        released = order.release_shopify_draft!(gid)
        return unresolve(gid, order_id, released.reason, released.error) unless released.ok?
      end
      count(outcome)
    rescue JobOrder::StaleDraftOrderError => e
      unresolve(gid, order_id, :draft_not_voidable, e)
    end

    def count(outcome) = @counts[outcome] += 1

    def unresolve(gid, order_id, reason, error)
      @unresolved_gids << gid
      @unresolved << "#{gid} of job order ##{order_id} (#{reason}): #{error&.message}"
    end
  end
end
