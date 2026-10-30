require "rails_helper"
require Rails.root.join("lib/concurrent_index_builder")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs
# outside the transactional wrapper on its own scratch table.
RSpec.describe ConcurrentIndexBuilder do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { "index_cib_scratch_on_val" }
  let(:builder) do
    Class.new(ActiveRecord::Migration[8.1]) do
      include ConcurrentIndexBuilder
      disable_ddl_transaction!
    end.new
  end

  before do
    conn.create_table(:cib_scratch, force: true) { |t| t.integer :val }
    conn.execute("INSERT INTO cib_scratch (val) VALUES (1), (1)")
  end

  after { conn.drop_table(:cib_scratch, if_exists: true) }

  def build
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(:cib_scratch, :val) }
  end

  def valid_flags
    conn.select_values(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relname = '#{index}' AND c.relnamespace = current_schema()::regnamespace
    SQL
  end

  def oid
    conn.select_value("SELECT '#{index}'::regclass::oid")
  end

  it "creates a missing index" do
    expect(valid_flags).to eq([])
    build
    expect(valid_flags).to eq([true])
  end

  it "leaves a valid index untouched" do
    build
    before_oid = oid
    build
    expect(valid_flags).to eq([true])
    expect(oid).to eq(before_oid)
  end

  it "rebuilds an INVALID leftover from an interrupted build, as a valid one" do
    # a UNIQUE concurrent build over duplicate values fails and leaves INVALID
    expect { conn.execute("CREATE UNIQUE INDEX CONCURRENTLY #{index} ON cib_scratch (val)") }
      .to raise_error(ActiveRecord::RecordNotUnique)
    expect(valid_flags).to eq([false])
    build
    expect(valid_flags).to eq([true])
  end

  it "raises on a valid index of that name with different columns, leaving it alone" do
    conn.add_index :cib_scratch, :id, name: index
    expect { build }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /index_cib_scratch_on_val/)
    expect(conn.indexes(:cib_scratch).find { |i| i.name == index }.columns).to eq(["id"])
  end

  it "raises on a valid index of that name with different uniqueness" do
    conn.execute("DELETE FROM cib_scratch")
    conn.add_index :cib_scratch, :val, name: index, unique: true
    expect { build }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch)
  end

  it "builds a unique index when asked" do
    conn.execute("DELETE FROM cib_scratch")
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(:cib_scratch, :val, unique: true) }
    expect(conn.indexes(:cib_scratch).find { |i| i.name == index }.unique).to be(true)
  end

  it "only treats an invalid index on the same table as a leftover" do
    conn.create_table(:cib_other, force: true) { |t| t.integer :val }
    conn.execute("INSERT INTO cib_other (val) VALUES (1), (1)")
    expect { conn.execute("CREATE UNIQUE INDEX CONCURRENTLY #{index} ON cib_other (val)") }.to raise_error(ActiveRecord::RecordNotUnique)
    # an INVALID index of this name on another table is not this table's to drop
    ActiveRecord::Migration.suppress_messages do
      expect(builder.send(:invalid_index?, :cib_scratch, index)).to be(false)
      expect(builder.send(:invalid_index?, :cib_other, index)).to be(true)
    end
  ensure
    conn.drop_table(:cib_other, if_exists: true)
  end

  it "refuses algorithm: and if_not_exists: from the caller" do
    expect { builder.add_index_concurrently(:cib_scratch, :val, algorithm: :default) }.to raise_error(ArgumentError)
    expect { builder.add_index_concurrently(:cib_scratch, :val, if_not_exists: false) }.to raise_error(ArgumentError)
  end

  it "refuses to run while a migration is being reverted" do
    allow(builder).to receive(:reverting?).and_return(true)
    expect { build }.to raise_error(ArgumentError, /reverted/)
  end
end
