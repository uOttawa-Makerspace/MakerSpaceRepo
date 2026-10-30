# frozen_string_literal: true

# Regularly reclaims Shopify drafts no job order points at (config/recurring.yml). The same code as
# `rake job_orders:sweep_orphan_drafts`: JobOrder::DraftSweep, which reports a run's unresolved drafts once. The job
# completes either way: raising would repeat the same report every hour for the same stuck draft.
class JobOrderDraftSweepJob < ApplicationJob
  queue_as :default

  def perform
    report = JobOrder::DraftSweep.run
    Rails.logger.info("[JobOrderDraftSweepJob] #{report.skipped ? 'skipped: another sweep is running' : report.counts.map { |k, v| "#{k}: #{v}" }.join(', ')}; unresolved: #{report.unresolved.size}")
  end
end
