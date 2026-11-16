# frozen_string_literal: true

# Regularly reclaims Shopify drafts no job order and no locker rental points at (config/recurring.yml). The job-order
# sweep is the same code as `rake job_orders:sweep_orphan_drafts`: JobOrder::DraftSweep; the locker one is
# LockerRental::DraftSweep. Each is independent (a failure of one never stops the other) and reports each unexpected exception class
# (and a deadlock) once per run, with the number of occurrences in the context, and the run's unresolved drafts once
# (a stable message). The job completes either way, on purpose: the
# sweep has already reported everything the tracker should see, so a failing job would only add a second, identical
# alert and retry hourly for the same stuck draft (and Solid Queue would keep a failed execution for each). A skipped
# run (another sweep running) is a normal, logged no-op here; only the rake, run by a person, exits non-zero for it.
class JobOrderDraftSweepJob < ApplicationJob
  queue_as :default

  def perform
    [JobOrder::DraftSweep, LockerRental::DraftSweep].each do |sweep|
      report = sweep.run
      Rails.logger.info("[JobOrderDraftSweepJob] #{sweep.name}: #{report.skipped ? 'skipped: another sweep is running' : report.counts.map { |k, v| "#{k}: #{v}" }.join(', ')}; unresolved: #{report.unresolved.size}")
    end
  end
end
