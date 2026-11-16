# frozen_string_literal: true

# Closes memberships whose checkout was never paid. See Membership::Expiry. Not scheduled for now: the entry is held
# in a comment in config/recurring.yml (see doc/maintenance.md, "Scheduled tasks"). Each membership that
# cannot be settled is reported by the model, so the job itself completes and the next run tries it again.
class MembershipExpiryJob < ApplicationJob
  queue_as :default

  def perform
    counts = Membership.expire_stale_pending!
    Rails.logger.info("[MembershipExpiryJob] #{counts.map { |outcome, n| "#{outcome}: #{n}" }.join(', ').presence || 'nothing stale'}")
  end
end
