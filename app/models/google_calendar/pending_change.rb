# frozen_string_literal: true

module GoogleCalendar
  # A change to Google Calendar that was asked for and that Google has not confirmed yet: a push of an event's
  # current state, or the removal of a destroyed event's Google copy. The row is written before the job is queued
  # and deleted by the job when Google has the change, so a job that could not be queued (the queue database
  # was down) or that ran out of attempts leaves the row behind, and GoogleCalendar::ResendJob queues it again.
  #
  # A push is one row per event, a removal one row per Google copy: asking twice leaves one row, and the jobs read
  # the event's state when they run, so a repeat is harmless.
  class PendingChange < ApplicationRecord
    self.table_name = "google_calendar_pending_changes"

    PUSH = "push"
    REMOVE = "remove"
    # A change is queued again when it has waited this long since it was asked for.
    RESEND_AFTER = 15.minutes
    # Queued again this many times at most; a change that still has not gone through is reported and left for staff.
    MAX_RESENDS = 5
    # Failures of the queue (its database being down, the queue refusing the job).
    QUEUE_ERRORS = [ActiveRecord::ActiveRecordError, ActiveJob::EnqueueError].freeze

    scope :due, -> { where(updated_at: ...RESEND_AFTER.ago, attempts: ...MAX_RESENDS) }

    # Records that the event's current state has to reach Google, and returns the row.
    def self.ask_push(event_id)
      ask(PUSH, event_id)
    end

    # Records that the Google copy has to be removed, and returns the row.
    def self.ask_removal(event_id, google_event_id, calendar_id)
      ask(REMOVE, event_id, google_event_id: google_event_id, calendar_id: calendar_id)
    end

    # Deletes the row once Google has the change, unless it was asked for again since +as_of+ (the time the job
    # that did the work started): that later ask has not been done yet.
    # +google_event_id+ names the copy of a removal; a push has none.
    def self.settle(action, event_id, as_of, google_event_id: nil)
      where(action: action, event_id: event_id, google_event_id: google_event_id, updated_at: ..as_of).delete_all
    end

    # Queues the job for every change that has waited long enough and been resent fewer than MAX_RESENDS times;
    # returns how many were queued.
    # The rows are claimed first, in one statement that counts the try and moves the row out of the due window,
    # so a run that overlaps this one claims none of them and queues nothing twice.
    def self.resend_due
      claim_due.sort_by(&:id).count(&:resend)
    end

    # Counts a try on every due row and returns the rows this call claimed.
    def self.claim_due
      sql = <<~SQL.squish
        UPDATE #{table_name} SET attempts = attempts + 1, updated_at = :now
        WHERE updated_at < :due_before AND attempts < :max_resends
        RETURNING *
      SQL
      find_by_sql([sql, { now: Time.current, due_before: RESEND_AFTER.ago, max_resends: MAX_RESENDS }])
    end
    private_class_method :claim_due

    # Queues the job that does this change. A queue that cannot take it is reported, not raised: the row stays
    # and the resend job queues it again.
    def enqueue
      if action == PUSH
        GoogleCalendar::EventPushJob.perform_later(event_id)
      else
        GoogleCalendar::EventDeleteJob.perform_later(google_event_id, calendar_id, event_id)
      end
      true
    rescue *QUEUE_ERRORS => e
      Rails.error.report(e, handled: true, context: { job: "GoogleCalendar::PendingChange", action: action, event_id: event_id })
      false
    end

    # Queues the job again for a row whose try was already counted by claim_due. The count is kept even when the
    # queue fails, so a queue that stays down also reaches the limit; the last try is reported as the one after
    # which staff have to look.
    def resend
      report_given_up if attempts >= MAX_RESENDS
      enqueue
    end

    def self.ask(action, event_id, **details)
      change = upsert({ action: action, event_id: event_id, attempts: 0, **details }, unique_by: %i[action event_id google_event_id], returning: %w[id]).first
      find(change["id"])
    end
    private_class_method :ask

    private

    def report_given_up
      Rails.error.report(RuntimeError.new("Google Calendar change was not confirmed after #{MAX_RESENDS} resends"),
                         handled: true, context: { action: action, event_id: event_id, change_id: id })
    end
  end
end
