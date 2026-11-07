# frozen_string_literal: true

# Tells the maintenance address about background jobs that failed or are stuck, once each. Solid Queue keeps a
# failed job in its failed executions until someone retries or discards it, and nothing else says it is there.
#
# Reported: failed executions, scheduled executions that are still waiting a while after they were due (the
# dispatcher is not running), and claimed executions that have run far too long (the job is hung). Only the last
# LOOKBACK is looked at, so switching the address on does not mail the whole history, and at most BATCH items go
# in one mail; the rest follow on the next run.
#
# Each item is claimed with Setting.claim under a key made of its kind and id before the mail goes, so a second
# run, or two at once, mails nobody twice. If the mail cannot be sent the claims are given back and the error
# is raised, so the next run tries again. The mail names the job class, queue, error class and the first line of
# the message, and ids; never the job's arguments.
class JobAlert
  Item = Data.define(:key, :kind, :job_id, :class_name, :queue_name, :detail)

  SCHEDULED_OVERDUE_AFTER = 15.minutes
  CLAIMED_OVERDUE_AFTER = 1.hour
  LOOKBACK = 1.day
  BATCH = 50
  MESSAGE_LENGTH = 200
  SENT = "sent"

  def initialize(now: Time.current)
    @now = now
  end

  # Returns the number of items mailed.
  def run
    recipient = Setting.maintenance_email
    return 0 if recipient.blank?

    claimed = unreported.first(BATCH).select { |item| Setting.claim(item.key, SENT) }
    deliver(claimed, recipient) if claimed.any?
    claimed.size
  end

  private

  def unreported
    items = failed_items + overdue_scheduled_items + overdue_claimed_items
    done = Setting.where(key: items.map(&:key), value: SENT).pluck(:key)
    items.reject { |item| done.include?(item.key) }
  end

  def failed_items
    SolidQueue::FailedExecution.where(created_at: window_start..).includes(:job).order(:id).map do |failure|
      item("failed:#{failure.id}", "failed", failure.job, "#{failure.exception_class}: #{first_line(failure.message)}")
    end
  end

  def overdue_scheduled_items
    SolidQueue::ScheduledExecution.where(scheduled_at: window_start..(@now - SCHEDULED_OVERDUE_AFTER)).includes(:job)
      .order(:id).map { |execution| overdue_item("scheduled", execution, "due #{execution.scheduled_at.utc.iso8601}") }
  end

  def overdue_claimed_items
    SolidQueue::ClaimedExecution.where(created_at: window_start..(@now - CLAIMED_OVERDUE_AFTER)).includes(:job)
      .order(:id).map { |execution| overdue_item("claimed", execution, "running since #{execution.created_at.utc.iso8601}") }
  end

  def overdue_item(kind, execution, detail)
    item("overdue:#{kind}:#{execution.job_id}", "overdue (#{kind})", execution.job, detail)
  end

  def item(key, kind, job, detail)
    Item.new(key: "job_alert:#{key}", kind: kind, job_id: job.id, class_name: job.class_name,
             queue_name: job.queue_name, detail: detail)
  end

  def window_start
    @now - LOOKBACK
  end

  def first_line(message)
    message.to_s.lines.first.to_s.strip.truncate(MESSAGE_LENGTH)
  end

  def deliver(items, recipient)
    JobAlertMailer.alert(items, recipient).deliver_now
  rescue StandardError
    items.each { |item| Setting.swap(item.key, SENT, nil) }
    raise
  end
end
