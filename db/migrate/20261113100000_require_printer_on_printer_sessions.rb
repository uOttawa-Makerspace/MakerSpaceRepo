# A printer session always belongs to a printer: printer_sessions.printer_id becomes
# NOT NULL. The staff dashboard shows the printer of every session in use, and only
# Printer#assign_to! creates sessions, always through the printer.
#
# Sessions without a printer are counted first and the migration refuses to run
# while any exist; they are never repaired or removed automatically (the printer they
# stand for is unknown). A CHECK is added NOT VALID, validated on its own (SHARE
# UPDATE EXCLUSIVE, writes keep flowing), then the column is set NOT NULL, which
# Postgres accepts without another table scan because the validated CHECK already
# proves it, and the CHECK, now redundant, is dropped. No DDL transaction wraps the
# migration, so each step commits alone and a failed run can be started again. Every
# ALTER waits for its lock for a few seconds at most and is retried, so a long
# transaction cannot queue printer assignments behind a deploy.
class RequirePrinterOnPrinterSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CHECK_NAME = "printer_sessions_printer_id_null_check"
  CHECK = "printer_id IS NOT NULL"
  LOCK_TIMEOUT = "3s"
  ATTEMPTS = 5
  RETRY_PAUSE = 2

  def up
    refuse_sessions_without_printer
    unless check_constraint_exists?(:printer_sessions, name: CHECK_NAME)
      with_lock_timeout { add_check_constraint :printer_sessions, CHECK, name: CHECK_NAME, validate: false }
    end
    with_lock_timeout { validate_check_constraint :printer_sessions, name: CHECK_NAME }
    with_lock_timeout { change_column_null :printer_sessions, :printer_id, false }
    with_lock_timeout { remove_check_constraint :printer_sessions, name: CHECK_NAME }
  end

  def down
    with_lock_timeout { change_column_null :printer_sessions, :printer_id, true }
    with_lock_timeout { remove_check_constraint :printer_sessions, name: CHECK_NAME, if_exists: true }
  end

  def refuse_sessions_without_printer
    count = select_value("SELECT COUNT(*) FROM printer_sessions WHERE printer_id IS NULL").to_i
    return if count.zero?

    raise "#{count} printer_sessions rows have no printer_id; " \
          "decide what to do with those rows before requiring a printer"
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

      say "printer_sessions: lock not available, retrying (attempt #{attempt} of #{ATTEMPTS})"
      sleep RETRY_PAUSE * attempt
      retry
    end
  end
end
