require "rails_helper"
require Rails.root.join("db/migrate/20261104000003_add_indexes_to_foreign_key_columns")
require Rails.root.join("db/migrate/20261104000004_add_foreign_keys_to_unenforced_references")

RSpec.describe AddForeignKeysToUnenforcedReferences do
  let(:migration) { described_class.new }

  def run_up
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  before do
    stub_const("#{described_class}::REFERENCES", [[:programs, :users, :user_id]])
    allow(migration).to receive(:sleep)
    allow(migration).to receive(:execute).and_call_original
  end

  it "adds each key in its own transaction under a 3 second lock timeout" do
    allow(migration).to receive(:add_foreign_key)
    expect(migration).to receive(:transaction).and_wrap_original { |original, *args, &block| original.call(*args, &block) }.once
    run_up
    expect(migration).to have_received(:execute).with("SET LOCAL lock_timeout = '3s'")
    expect(migration).to have_received(:add_foreign_key).with(:programs, :users, column: :user_id, validate: false, if_not_exists: true)
  end

  it "retries a lock timeout and succeeds" do
    calls = 0
    allow(migration).to receive(:add_foreign_key) do
      calls += 1
      raise ActiveRecord::LockWaitTimeout, "busy" if calls < 3
    end
    expect { run_up }.not_to raise_error
    expect(calls).to eq(3)
    expect(migration).to have_received(:sleep).with(2).ordered
    expect(migration).to have_received(:sleep).with(4).ordered
  end

  it "gives up after three attempts" do
    calls = 0
    allow(migration).to receive(:add_foreign_key) { calls += 1; raise ActiveRecord::LockWaitTimeout, "busy" }
    expect { run_up }.to raise_error(ActiveRecord::LockWaitTimeout)
    expect(calls).to eq(3)
  end

  it "does not retry other errors" do
    calls = 0
    allow(migration).to receive(:add_foreign_key) { calls += 1; raise ActiveRecord::StatementInvalid, "bad" }
    expect { run_up }.to raise_error(ActiveRecord::StatementInvalid)
    expect(calls).to eq(1)
  end
end

RSpec.describe AddIndexesToForeignKeyColumns do
  it "leaves every foreign key column of the next migration with an index that leads with it" do
    AddForeignKeysToUnenforcedReferences::REFERENCES.each do |table, _parent, column, _on_delete|
      leading = ActiveRecord::Base.connection.indexes(table).map { |i| Array(i.columns).first }
      expect(leading).to include(column.to_s), "no index on #{table}.#{column}"
    end
  end
end

require Rails.root.join("db/migrate/20261104000005_validate_foreign_keys_on_unenforced_references")

RSpec.describe ValidateForeignKeysOnUnenforcedReferences do
  it "does not wrap the validations in one DDL transaction, so each commits on its own" do
    expect(described_class.disable_ddl_transaction).to be(true)
  end

  it "can be run again: validated keys are skipped" do
    run = -> { ActiveRecord::Migration.suppress_messages { described_class.new.up } }
    expect { run.call; run.call }.not_to raise_error
  end
end
