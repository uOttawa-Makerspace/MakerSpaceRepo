# frozen_string_literal: true

# Regularly reclaims Shopify drafts no job order points at (config/recurring.yml). The same code as
# `rake job_orders:sweep_orphan_drafts`: JobOrder::DraftSweep.
class JobOrderDraftSweepJob < ApplicationJob
  queue_as :default

  class Unresolved < StandardError; end

  def perform
    report = JobOrder::DraftSweep.run
    Rails.logger.info("[JobOrderDraftSweepJob] #{report.counts.map { |k, v| "#{k}: #{v}" }.join(', ')}")
    # a failed job is visible in Mission Control; the next run retries what is left
    raise Unresolved, report.unresolved.join("; ") unless report.ok?
  end
end
