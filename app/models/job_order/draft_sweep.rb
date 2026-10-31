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
# - decided and acted on per draft in ONE locked operation (JobOrder.reconcile_orphan_draft!): under the order's row
#   lock the order is re-read, kept when the database backs it (JobOrder#backs_draft?: a live order waiting for
#   payment whose stored shopify_draft_order_id is this draft), otherwise the draft is fetched and deleted (never when
#   Shopify reports it paid) and the stored id cleared. Deciding and deleting under one lock is what keeps a live
#   invoice: a transition into COMPLETED keeps the order's stored id, so a draft that was an orphan a moment ago can
#   become the invoice, and only the lock orders that against the delete. An order whose row is gone has no lock to
#   take: JobOrder.reconcile_orphan_draft! settles its draft the same way (marker re-checked, unless paid);
# - kill switch: the orphans are counted BEFORE anything is deleted, and when there are more than the cap
#   (MAX_DELETES, or the explicit `run(max_deletes:)` / rake CONFIRM_MAX_DELETES=n override) NOTHING is deleted and the
#   run is unresolved: a sweep run against the wrong or a restored database would otherwise delete every draft. That
#   count is unlocked and can go stale (drafts become orphans while the run goes on), so the cap is ALSO enforced at
#   delete time: once the run has deleted the cap, a draft the database does not back is no longer deleted (decided
#   under its lock) and is unresolved; a backed one is still kept;
# - fail closed: any Shopify or lock error leaves the draft and lists it as unresolved;
# - one sweep at a time (a Postgres advisory lock): a second one is skipped (the rake exits 2).
#
# Reporting: an unexpected exception and a :deadlock are reported with their backtrace and the first draft's gid, each
# exception CLASS at most once per run, with the number of occurrences in the context (a database outage must not send
# one report per draft). Only a lost connection (ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionFailed)
# aborts the run: the rest is unresolved. A per-row database error (a cancelled query, a constraint violation ...) is
# that draft's own failure. Everything else that is left (Shopify refusals, a busy order, the kill switch ...) is listed
# in the Report and told ONCE per run, with a stable message (so the error tracker groups it) and the gids and counts
# in the context (at most REPORTED_LIMIT). The run-level lines (listing problems, the cap, the stop) come BEFORE the
# per-draft lines, so the REPORTED_LIMIT cut never removes them. The reports are sent even when something escapes the
# run (an unlock on a dead connection). Nothing escapes #run: an exception out of the run itself (the unlock, the
# kill-switch count, the loop) is recorded as the run-level line "aborted: <class>: <message>", the drafts not
# examined are listed as unresolved, the reports are sent and the Report is returned (so the job completes and the
# rake exits 1 with the list). Only an Interrupt / SignalException (any non-StandardError) propagates, after the same flush, whatever else failed
# meanwhile; it is logged at warn level and told in the summary, not reported as an error. A step of the flush that
# raises is reported to Rails.error and the others still run.
# Run by `rake job_orders:sweep_orphan_drafts` and, regularly, by JobOrderDraftSweepJob (config/recurring.yml).
class JobOrder
  class DraftSweep
    PAGE_SIZE = 50
    MAX_PAGES = 1000
    MAX_DELETES = 200
    REPORTED_LIMIT = 20 # the unresolved lines and gids told in the run's report
    SUMMARY_MESSAGE = "job order draft sweep: unresolved drafts"
    LOCK_KEY = Zlib.crc32("JobOrder::DraftSweep")
    OUTCOMES = %i[kept deleted cleared unmarked].freeze

    RUN_WHERE = "JobOrder::DraftSweep#run"
    RECONCILE_WHERE = "JobOrder::DraftSweep#reconcile"

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
      @run_lines = [] # unresolved lines about the run itself (listing, kill switch), before the per-draft lines
      @unresolved = [] # one line per unresolved draft
      @unresolved_gids = []
      @unmarked = Set.new
      @errors = {} # [where, exception class] => { error:, gid:, order_id:, count: }: reported once each, at the end of the run
      @capped = [] # orphans met after the run had deleted the cap
      @drafts = [] # the listed [gid, order id] pairs
      @done = 0 # the drafts before this index were examined
      @stop = nil # why the run stopped early: the run-level line about the drafts left unexamined
      @escaping = nil # the Interrupt / SignalException (or other non-StandardError) in flight: re-raised after the flush
      @stopped_by = nil # the connection error that stopped the run (see #database_error?)
    end

    def run
      report = nil
      aborted = nil
      begin
        report = with_sweep_lock { sweep }
      rescue StandardError => e
        aborted = e
      rescue Exception => e # rubocop:disable Lint/RescueException -- Interrupt, SignalException ...: flushed below, then propagated
        @escaping ||= e
      end
      report = flush(report, aborted)
      raise @escaping if @escaping # whatever else failed meanwhile (an unlock error replacing it, a report error)

      report
    end

    private

    def with_sweep_lock
      ActiveRecord::Base.with_connection do |conn|
        return build_report(skipped: true) unless conn.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")

        begin
          yield
        rescue SignalException => e
          @escaping ||= e # kept here: an error raised by the unlock below would replace it in flight
          raise
        ensure
          conn.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
        end
      end
    end

    def sweep
      # looked up once, first: a missing Completed row fails here, at one defined point, and #run reports it as a
      # run-level abort (not once per draft)
      @completed_id = JobStatus.completed.id
      @drafts = list_payable_drafts
      if over_cap?(@drafts)
        @done = @drafts.size # nothing is examined on purpose: the kill switch's own line says so
      else
        reconcile_all
      end
      build_report
    end

    # Something escaped the run: an error is told as the first run-level line, an Interrupt / SignalException (not an
    # error: logged at warn level, in the summary only) before it; the drafts not examined are unresolved, the error
    # is reported (once per class, with the others).
    def abort_run(error)
      if error
        note_error(error, nil, nil, where: RUN_WHERE)
        @run_lines.unshift("aborted: #{error.class}: #{error.message}")
      end
      if @escaping
        Rails.logger.warn("[JobOrder::DraftSweep] interrupted: #{@escaping.class}: #{@escaping.message}")
        @run_lines.unshift("interrupted: #{@escaping.class}#{": #{@escaping.message}" if @escaping.message.present?}")
      end
      stop_before(@done, "the run was aborted")
      build_report
    end

    # The end of the run, which never fails silently and never raises: each step that raises is reported (minimal
    # context) and the next one still happens; a report is always returned.
    def flush(report, error)
      report = guarded("abort_run") { abort_run(error) } if error || @escaping
      report ||= guarded("build_report") { build_report } || failed_report
      guarded("report_errors") { report_errors }
      guarded("report_once") { report_once(report) } unless report.ok?
      report
    end

    def guarded(step)
      yield
    rescue StandardError => e
      begin
        Rails.error.report(e, handled: true, context: { where: RUN_WHERE, step: step })
      rescue StandardError
        nil # the flush has nowhere left to tell it
      end
      nil
    end

    def failed_report
      Report.new(counts: OUTCOMES.index_with(0), unresolved: ["the run's report could not be built"], unresolved_gids: [], skipped: false)
    end

    # Stops at a lost connection (the rest unresolved, not examined). The deletes are held to the cap: the up-front
    # count (#over_cap?) is unlocked, so drafts that became orphans during the run are caught here.
    def reconcile_all
      @drafts.each_with_index do |(gid, order_id), index|
        @done = index
        if @stopped_by
          stop_before(index, "a database error stopped the run (#{@stopped_by.class})")
          return
        end

        reconcile(gid, order_id)
      end
      @done = @drafts.size
    end

    # The drafts from index `from` on were not examined: unresolved, with the reason as a run-level line.
    def stop_before(from, reason)
      rest = @drafts.drop(from)
      @done = @drafts.size
      return if rest.empty?

      @unresolved_gids.concat(rest.map(&:first))
      @stop = "#{rest.size} draft(s) not examined, #{reason}"
    end

    # The run-level lines, first in the report: the cap met during the run, then the database stop.
    def run_lines
      lines = @run_lines.dup
      if @capped.any?
        lines << "#{@capped.size} orphan draft(s) found during the run beyond the cap of #{@max_deletes}: NOT deleted" \
                 "#{override_hint(@max_deletes + @capped.size)}"
      end
      lines << @stop if @stop
      lines
    end

    def override_hint(cap) = ". Check that this is the right database, then rerun with an explicit cap " \
                             "(rake CONFIRM_MAX_DELETES=#{cap}, or JobOrder::DraftSweep.run(max_deletes: #{cap}))"

    # The kill switch: counts the drafts the database does not back, before anything is deleted. Over the cap, nothing
    # is deleted. Read without a lock: it is a count, not a decision (the per-draft check under the lock decides
    # again, and #reconcile_all holds the deletes to the cap even if the count has gone stale). Up to the cap there is
    # nothing to count; over it, one query reads what JobOrder.backs_draft? needs for all the orders.
    def over_cap?(drafts)
      return false if drafts.size <= @max_deletes

      rows = backing_rows(drafts.map(&:last))
      orphans = drafts.count { |gid, order_id| !(rows[order_id] && JobOrder.backs_draft?(gid, completed_id: @completed_id, **rows[order_id])) }
      return false if orphans <= @max_deletes

      @run_lines << "#{orphans} orphan draft(s) found, more than the cap of #{@max_deletes}: NOTHING was deleted" \
                     "#{override_hint(orphans)}"
      true
    end

    # order id => the plain values JobOrder.backs_draft? decides on, for all the orders in ONE query (the latest status
    # is JobOrder::LATEST_STATUS_ID_SQL, the one definition the instance path uses too).
    def backing_rows(order_ids)
      JobOrder.where(id: order_ids.uniq).pluck(:id, :is_deleted, :shopify_draft_order_id, Arel.sql(JobOrder::LATEST_STATUS_ID_SQL))
              .to_h { |id, deleted, stored, status_id| [id, { deleted: deleted, stored_gid: stored, status_id: status_id }] }
    end

    def build_report(skipped: false)
      Report.new(counts: OUTCOMES.index_with { |o| o == :unmarked ? @unmarked.size : @counts[o] }, unresolved: run_lines + @unresolved,
                 unresolved_gids: @unresolved_gids.uniq, skipped: skipped)
    end

    # The run's one summary report. The message is stable (the tracker groups by it); what varies is in the context.
    def report_once(report)
      Rails.error.report(Unresolved.new(SUMMARY_MESSAGE), handled: true,
                         context: { unresolved_count: report.unresolved.size, unresolved_total: report.unresolved_gids.size,
                                    unresolved_draft_order_ids: report.unresolved_gids.first(REPORTED_LIMIT),
                                    unresolved: report.unresolved.first(REPORTED_LIMIT), counts: report.counts,
                                    where: RUN_WHERE })
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
          @run_lines << "listing open drafts: the page cursor #{cursor.inspect} repeated, the listing is incomplete"
          return found.to_a
        end
      end
      @run_lines << "listing open drafts: more than #{MAX_PAGES} pages, the listing is incomplete"
      found.to_a
    rescue StandardError => e
      Rails.logger.error("[JobOrder::DraftSweep] listing failed: #{e.class}: #{e.message}")
      @run_lines << "listing open drafts (#{e.class}): #{e.message}"
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
      tags = node["tags"]
      return nil unless JobOrder::PAYABLE_DRAFT_STATUSES.include?(node["status"]) && JobOrder.draft_order_processable?(tags)

      order_id = JobOrder.draft_marker_order_id(tags)
      return [node["id"], order_id] if order_id && node["id"].present?

      @unmarked << (node["id"].presence || [:no_id, @unmarked.size]) # one draft on two pages is one
      nil
    end

    def reconcile(gid, order_id)
      may_delete = @counts[:deleted] < @max_deletes
      result = JobOrder.reconcile_orphan_draft!(order_id, gid, may_delete: may_delete)
      return count(result.value) if result.ok?
      return capped(gid) if result.reason == :delete_cap

      note_error(result.error, gid, order_id) if result.reason == :deadlock
      unresolve(gid, order_id, result.reason, result.error)
    rescue StandardError => e
      note_error(e, gid, order_id)
      @stopped_by ||= e if database_error?(e)
      unresolve(gid, order_id, :unexpected, e)
    end

    # Only a lost connection will hit every draft the same way, so only it stops the run. A plain
    # ActiveRecord::StatementInvalid (a cancelled query, a constraint violation ...) belongs to its draft and does not
    # stop the run, because stopping would buy nothing: (1) each exception class is reported once per run, so a
    # failure that hits every draft is still one report with its count, not one per draft; (2) every lock wait is
    # bounded by lock_timeout (ApplicationRecord.own_transaction, SET LOCAL lock_timeout), so a draft that cannot be had fails fast and the run moves
    # on to the next instead of hanging. Stopping on any StatementInvalid would leave the healthy drafts unexamined
    # for one bad row.
    def database_error?(error) = error.is_a?(ActiveRecord::ConnectionNotEstablished) || error.is_a?(ActiveRecord::ConnectionFailed)

    # Logs the failure and keeps the first exception of its class for #report_errors (its class and backtrace, for the
    # tracker), counting the others.
    def note_error(error, gid, order_id, where: RECONCILE_WHERE)
      Rails.logger.error("[JobOrder::DraftSweep] #{gid}: #{error.class}: #{error.message}")
      (@errors[[where, error.class]] ||= { error: error, gid: gid, order_id: order_id, where: where, count: 0 })[:count] += 1
    end

    # Each exception class once per run, with how many drafts it hit.
    def report_errors
      @errors.each_value do |first|
        guarded("report_errors") do
          Rails.error.report(first[:error], handled: true,
                                            context: { draft_order_id: first[:gid], job_order_id: first[:order_id],
                                                       occurrences: first[:count], where: first[:where] })
        end
      end
    end

    def capped(gid)
      @capped << gid
      @unresolved_gids << gid
    end

    def count(outcome) = @counts[outcome] += 1

    def unresolve(gid, order_id, reason, error)
      @unresolved_gids << gid
      @unresolved << "#{gid} of job order ##{order_id} (#{reason}): #{error&.message}"
    end
  end
end
