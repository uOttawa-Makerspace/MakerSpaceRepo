# frozen_string_literal: true

module GoogleCalendar
  # Queues again the Google Calendar pushes and removals that were asked for and never confirmed (see
  # PendingChange): the ones whose job could not be queued, or ran out of attempts. Runs on a schedule
  # (config/recurring.yml). Safe to run at any time and twice: the push and delete jobs read the current state and
  # treat an already-removed copy as done.
  class ResendJob < ApplicationJob
    queue_as :default

    def perform
      PendingChange.resend_due
    end
  end
end
