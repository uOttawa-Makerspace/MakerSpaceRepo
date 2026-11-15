# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115140100_create_payment_ledger_entries")

# DDL is transactional in the test database: each example takes the table (and the locker payment column that
# points at it) off first, and the rollback restores the real schema afterwards.
RSpec.describe CreatePaymentLedgerEntries do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    connection.remove_reference(:locker_payments, :ledger_entry, foreign_key: { to_table: :payment_ledger_entries })
    connection.drop_table(:payment_ledger_entries)
    connection.execute("DROP FUNCTION #{described_class::FUNCTION}()")
  end

  after { LockerPayment.reset_column_information }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def run(sql)
    connection.transaction(requires_new: true) { connection.execute(sql) }
  end

  def insert(ref, kind: "payment", reversed: "NULL", amount: "10.00", provider: "shopify")
    connection.transaction(requires_new: true) do
      connection.select_value(<<~SQL.squish)
        INSERT INTO payment_ledger_entries (provider, provider_ref, amount, kind, reversed_entry_id, created_at, updated_at)
        VALUES ('#{provider}', '#{ref}', #{amount}, '#{kind}', #{reversed}, now(), now()) RETURNING id
      SQL
    end
  end

  def count = connection.select_value("SELECT COUNT(*) FROM payment_ledger_entries").to_i

  it "keeps one payment and at most one reversal of it per provider ref" do
    migrate(:up)

    paid = insert("1001")
    insert("1001", kind: "reversal", reversed: paid)
    expect { insert("1001") }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert("1001", kind: "reversal", reversed: paid) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert("1002", kind: "reversal") }.to raise_error(ActiveRecord::StatementInvalid, /reversal_has_entry_check/)
    expect { insert("1003", reversed: paid) }.to raise_error(ActiveRecord::StatementInvalid, /reversal_has_entry_check/)
    expect { insert("1004", amount: "-1") }.to raise_error(ActiveRecord::StatementInvalid, /amount_check/)
    expect { insert("1005", kind: "refund") }.to raise_error(ActiveRecord::StatementInvalid, /kind_check/)
    expect(count).to eq(2)
  end

  it "refuses a reversal that points at a reversal, or at a payment of another provider or provider ref" do
    migrate(:up)
    paid = insert("1001")
    reversal = insert("1001", kind: "reversal", reversed: paid)
    fk = /fk_payment_ledger_entries_reversed_entry/

    expect { insert("1001", kind: "reversal", reversed: reversal) }.to raise_error(ActiveRecord::InvalidForeignKey, fk)
    expect { insert("1002", kind: "reversal", reversed: insert("1009")) }.to raise_error(ActiveRecord::InvalidForeignKey, fk)
    expect { insert("1003", kind: "reversal", reversed: insert("1003", provider: "other")) }
      .to raise_error(ActiveRecord::InvalidForeignKey, fk)
    expect(connection.select_value("SELECT COUNT(*) FROM payment_ledger_entries WHERE kind = 'reversal'").to_i).to eq(1)
  end

  it "refuses every update, delete and truncate, leaving the rows as they were" do
    migrate(:up)
    id = insert("1001")

    expect { run("UPDATE payment_ledger_entries SET amount = 0 WHERE id = #{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only: UPDATE refused/)
    expect { run("DELETE FROM payment_ledger_entries WHERE id = #{id}") }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only: DELETE refused/)
    expect { run("TRUNCATE payment_ledger_entries") }
      .to raise_error(ActiveRecord::StatementInvalid, /append-only: TRUNCATE refused/)
    expect(connection.select_rows("SELECT provider_ref, amount FROM payment_ledger_entries")).to eq([["1001", BigDecimal("10.00")]])
  end

  it "removes the table, its triggers and their function on down, and runs again" do
    migrate(:up)
    migrate(:down)

    expect(connection.table_exists?(:payment_ledger_entries)).to be(false)
    expect(connection.select_value("SELECT COUNT(*) FROM pg_proc WHERE proname = '#{described_class::FUNCTION}'")).to eq(0)
    migrate(:up)
    expect(connection.select_values(<<~SQL.squish)).to eq(%w[payment_ledger_entries_no_change payment_ledger_entries_no_truncate])
      SELECT tgname FROM pg_trigger WHERE tgrelid = 'payment_ledger_entries'::regclass AND NOT tgisinternal ORDER BY tgname
    SQL
  end
end
