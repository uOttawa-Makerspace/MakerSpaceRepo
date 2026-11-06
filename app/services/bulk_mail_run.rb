# frozen_string_literal: true

# Makes a hand-run bulk mail task safe to run twice. Progress for one task and period (a year, a day) is a
# Setting holding the id of the last user already handled, or "done". Each batch is claimed with a compare and
# swap before it is mailed, so a second run in the same period mails nobody, an interrupted run continues after
# the last claimed batch, and two runs at once cannot mail the same batch. If mailing a batch raises, its claim
# is given back so the next run retries it.
class BulkMailRun
  DONE = "done"

  def initialize(name, period, force: false)
    @key = "bulk_mail:#{name}:#{period}"
    @force = force
  end

  def done?
    Setting.get(@key) == DONE && !@force
  end

  # Yields the users of +scope+ in id order, +size+ at a time, and returns the number of batches mailed.
  def each_batch(scope, size)
    reset if @force
    batches = 0
    while (progress = current_progress) != DONE
      batch = scope.where("users.id > ?", progress.to_i).reorder(:id).limit(size).to_a
      if batch.empty?
        Setting.swap(@key, progress, DONE)
        break
      end
      break unless Setting.swap(@key, progress, batch.last.id.to_s) # another run claimed it first
      mail_claimed(batch, progress, batch.last.id.to_s) { |users| yield users }
      batches += 1
    end
    batches
  end

  # Yields one user at a time, each claimed before it is mailed, so a failure partway through a run repeats
  # only the user whose mail failed. Returns the number of users mailed.
  def each_user(scope, &)
    each_batch(scope, 1) { |users| yield users.first }
  end

  private

  # The stored value is nil (or empty), "done" or the id of the last user handled; anything else is not ours to guess at.
  def current_progress
    value = Setting.get(@key)
    if value == ""
      Setting.swap(@key, "", nil) # an emptied row means start over
      value = nil
    end
    return value if value.nil? || value == DONE || value.match?(/\A\d+\z/)
    raise "Unexpected progress #{value.inspect} in setting #{@key}; fix or delete that row to continue"
  end

  def reset
    Setting.insert({ key: @key }, unique_by: :key)
    Setting.where(key: @key).update_all(value: nil, updated_at: Time.current)
    @force = false
  end

  def mail_claimed(batch, previous, claimed)
    yield batch
  rescue StandardError, SignalException
    # Best effort: also covers Ctrl-C (Interrupt) and SIGTERM, the usual ways a hand-run task is stopped.
    # Only SIGKILL or a crash of the process leaves the claimed batch marked as sent.
    Setting.swap(@key, claimed, previous)
    raise
  end
end
