# frozen_string_literal: true

# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Bound for every lock wait of a money or cart transaction (bound_lock_waits!): a row held long
  # elsewhere must not pin a web thread. Past it, Postgres raises ActiveRecord::LockWaitTimeout.
  LOCK_TIMEOUT = "5s"

  # A caller's transaction is an open, joinable one. (The spec suite's fixture transaction is
  # not joinable: it is not a caller transaction.)
  def self.caller_transaction_open?
    connection.transaction_open? && connection.current_transaction.joinable?
  end

  # Runs the block as its OWN top-level transaction with every lock wait bounded
  # (bound_lock_waits!; COMMIT/ROLLBACK ends the setting). Inside a caller's transaction it raises
  # ArgumentError instead of joining it: the SET LOCAL would otherwise apply to the rest of the
  # caller's transaction. This is the only place a money/cart path changes a session setting.
  def self.own_transaction(name)
    raise ArgumentError, "#{name} must run as its own transaction" if caller_transaction_open?

    transaction do
      bound_lock_waits!
      yield
    end
  end

  # SET LOCAL lock_timeout = LOCK_TIMEOUT for the rest of the current transaction.
  def self.bound_lock_waits!
    connection.execute("SET LOCAL lock_timeout = #{connection.quote(LOCK_TIMEOUT)}")
  end
end
