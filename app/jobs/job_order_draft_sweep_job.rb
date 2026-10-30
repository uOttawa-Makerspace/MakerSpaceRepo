# frozen_string_literal: true

# Regularly reclaims Shopify drafts no job order points at (config/recurring.yml). The same code as
# `rake job_orders:sweep_orphan_drafts`: JobOrder::DraftSweep, which reports an unexpected error or deadlock
# individually and the run's unresolved drafts once (a stable message). The job completes either way, on purpose: the
# sweep has already reported everything the tracker should see, so a failing job would only add a second, identical
# alert and retry hourly for the same stuck draft (and Solid Queue would keep a failed execution for each). A skipped
# run (another sweep running) is a normal, logged no-op here; only the rake, run by a person, exits non-zero for it.
class JobOrderDraftSweepJob < ApplicationJob
  queue_as :default

  def perform
    report = JobOrder::DraftSweep.run
    Rails.logger.info("[JobOrderDraftSweepJob] #{report.skipped ? 'skipped: another sweep is running' : report.counts.map { |k, v| "#{k}: #{v}" }.join(', ')}; unresolved: #{report.unresolved.size}")
  end
end
