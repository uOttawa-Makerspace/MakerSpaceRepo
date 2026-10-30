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
# - decided and acted on per draft in ONE locked operation (JobOrder#reconcile_orphan_draft!): under the order's row
#   lock the order is re-read, kept when the database backs it (JobOrder#backs_draft?: a live order waiting for
#   payment whose stored shopify_draft_order_id is this draft), otherwise the draft is fetched and deleted (never when
#   Shopify reports it paid) and the stored id cleared. Deciding and deleting under one lock is what keeps a live
#   invoice: a transition into COMPLETED keeps the order's stored id, so a draft that was an orphan a moment ago can
#   become the invoice, and only the lock orders that against the delete. An order whose row is gone has no lock to
#   take: its draft is deleted the same way (unless paid);
# - kill switch: the orphans are counted BEFORE anything is deleted, and when there are more than the cap
#   (MAX_DELETES, or the explicit `run(max_deletes:)` / rake CONFIRM_MAX_DELETES=n override) NOTHING is deleted and the
#   run is unresolved: a sweep run against the wrong or a restored database would otherwise delete every draft;
# - fail closed: any Shopify or lock error leaves the draft and lists it as unresolved;
# - one sweep at a time (a Postgres advisory lock): a second one is skipped (the rake exits 2).
#
# Reporting: an unexpected exception and a :deadlock are reported individually, with their backtrace and the draft's
# gid. Everything else that is left (Shopify refusals, a busy order, the kill switch ...) is listed in the Report and
# told ONCE per run, with a stable message (so the error tracker groups it) and the gids and counts in the context.
# Run by `rake job_orders:sweep_orphan_drafts` and, regularly, by JobOrderDraftSweepJob (config/recurring.yml).
class JobOrder
  class DraftSweep
    PAGE_SIZE = 50
    MAX_PAGES = 1000
    MAX_DELETES = 200
    SUMMARY_MESSAGE = "job order draft sweep: unresolved drafts"
    LOCK_KEY = Zlib.crc32("JobOrder::DraftSweep")
    OUTCOMES = %i[kept deleted cleared unmarked].freeze

    class Unresolved < StandardError; end

    # counts: outcome => number (unmarked: distinct drafts); unresolved: ["<draft gid> (<reason>): <message>", ...]; unresolved_gids: the drafts
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
      @unmarked = Set.new
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
      drafts = list_payable_drafts
      reconcile_all(drafts) unless over_cap?(drafts)
      build_report
    end

    def reconcile_all(drafts) = drafts.each { |gid, order_id| reconcile(gid, order_id) }

    # The kill switch: counts the drafts the database does not back, before anything is deleted. Over the cap, nothing
    # is deleted (the per-draft check under the lock decides again, so it can only delete fewer). Read without a lock:
    # it is a count, not a decision.
    def over_cap?(drafts)
      orders = JobOrder.where(id: drafts.map(&:last)).index_by(&:id)
      orphans = drafts.count { |gid, order_id| !orders[order_id]&.backs_draft?(gid) }
      return false if orphans <= @max_deletes

      @unresolved << "#{orphans} orphan draft(s) found, more than the cap of #{@max_deletes}: NOTHING was deleted. " \
                     "Check that this is the right database, then rerun with an explicit cap " \
                     "(rake CONFIRM_MAX_DELETES=#{orphans}, or JobOrder::DraftSweep.run(max_deletes: #{orphans}))"
      true
    end

    def build_report(skipped: false)
      Report.new(counts: OUTCOMES.index_with { |o| o == :unmarked ? @unmarked.size : @counts[o] }, unresolved: @unresolved,
                 unresolved_gids: @unresolved_gids.uniq, skipped: skipped)
    end

    # The run's one summary report. The message is stable (the tracker groups by it); what varies is in the context.
    def report_once(report)
      Rails.error.report(Unresolved.new(SUMMARY_MESSAGE), handled: true,
                         context: { unresolved_count: report.unresolved.size, unresolved_draft_order_ids: report.unresolved_gids,
                                    unresolved: report.unresolved.first(20), counts: report.counts,
                                    where: "JobOrder::DraftSweep#run" })
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

      @unmarked << (node["id"].presence || [:no_id, @unmarked.size]) # one draft on two pages is one
      nil
    end

    def reconcile(gid, order_id)
      result = JobOrder.find_by(id: order_id)&.reconcile_orphan_draft!(gid)
      result = delete_without_order(gid) if result.nil? || result.reason == :order_missing
      return count(result.value) if result.ok?

      report_error(result.error, gid, order_id) if result.reason == :deadlock
      unresolve(gid, order_id, result.reason, result.error)
    rescue StandardError => e
      report_error(e, gid, order_id)
      unresolve(gid, order_id, :unexpected, e)
    end

    # The order row is gone (never there, or hard-deleted mid-sweep): no lock to take and nothing to keep the draft for.
    def delete_without_order(gid)
      JobOrder::TransitionResult.done(DraftDeletion.delete_unless_completed!(gid))
    rescue JobOrder::StaleDraftOrderError => e
      JobOrder::TransitionResult.refused(:draft_not_voidable, e)
    end

    # The exception itself, so the tracker has its class and backtrace.
    def report_error(error, gid, order_id)
      Rails.logger.error("[JobOrder::DraftSweep] #{gid}: #{error.class}: #{error.message}")
      Rails.error.report(error, handled: true,
                                context: { draft_order_id: gid, job_order_id: order_id, where: "JobOrder::DraftSweep#reconcile" })
    end

    def count(outcome) = @counts[outcome] += 1

    def unresolve(gid, order_id, reason, error)
      @unresolved_gids << gid
      @unresolved << "#{gid} of job order ##{order_id} (#{reason}): #{error&.message}"
    end
  end
end
