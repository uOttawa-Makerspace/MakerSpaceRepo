# A card row always has a number: NOT NULL plus a CHECK that it contains a
# non-whitespace character, whitespace as Postgres sees it (spaces, tabs and
# newlines count as blank).
#
# Rows without a usable number are counted first and the migration refuses to run
# while any exist; they are never repaired or removed automatically (the card they
# stand for is unknown). The CHECK is added NOT VALID, validated on its own
# (SHARE UPDATE EXCLUSIVE, writes keep flowing) and only then is the column set NOT
# NULL, which Postgres accepts without another table scan because the validated
# CHECK already proves it. No DDL transaction wraps the migration, so each step
# commits alone and a failed run can be started again. Every ALTER waits for its
# lock for a few seconds at most and is retried, so a long transaction cannot
# queue the card taps behind a deploy.
class RequireCardNumberOnRfids < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CHECK_NAME = "rfids_card_number_present_check"
  CHECK = "card_number IS NOT NULL AND card_number ~ '\\S'"
  LOCK_TIMEOUT = "3s"
  ATTEMPTS = 5
  RETRY_PAUSE = 2

  def up
    refuse_unusable_numbers
    unless check_constraint_exists?(:rfids, name: CHECK_NAME)
      with_lock_timeout { add_check_constraint :rfids, CHECK, name: CHECK_NAME, validate: false }
    end
    with_lock_timeout { validate_check_constraint :rfids, name: CHECK_NAME }
    with_lock_timeout { change_column_null :rfids, :card_number, false }
  end

  def down
    with_lock_timeout { change_column_null :rfids, :card_number, true }
    with_lock_timeout { remove_check_constraint :rfids, name: CHECK_NAME, if_exists: true }
  end

  def refuse_unusable_numbers
    count = select_value("SELECT COUNT(*) FROM rfids WHERE card_number IS NULL OR card_number !~ '\\S'").to_i
    return if count.zero?

    raise "#{count} rfids rows have no usable card_number (NULL or blank); " \
          "decide what to do with those rows before requiring a number"
  end

  private

  def with_lock_timeout
    attempt = 0
    begin
      attempt += 1
      transaction do
        execute "SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'"
        yield
      end
    rescue ActiveRecord::LockWaitTimeout
      raise if attempt >= ATTEMPTS

      say "rfids: lock not available, retrying (attempt #{attempt} of #{ATTEMPTS})"
      sleep RETRY_PAUSE * attempt
      retry
    end
  end
end
