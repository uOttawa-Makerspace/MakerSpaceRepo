require "rails_helper"
require Rails.root.join("lib/concurrent_index_builder")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs
# outside the transactional wrapper on its own scratch tables, which are
# (re)created before and dropped after every example, however it ends.
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
    conn.create_table(:cib_scratch, force: true) do |t|
      t.integer :val
      t.text :txt
    end
    conn.create_table(:cib_other, force: true) { |t| t.integer :val }
    conn.execute("INSERT INTO cib_scratch (val) VALUES (1), (1)")
    conn.execute("INSERT INTO cib_other (val) VALUES (1), (1)")
  end

  after do
    conn.drop_table(:cib_scratch, if_exists: true)
    conn.drop_table(:cib_other, if_exists: true)
  end

  def build(columns = :val, **options)
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(:cib_scratch, columns, **options) }
  end

  def found(table = :cib_scratch, name = index)
    conn.indexes(table).find { |i| i.name == name }
  end

  def oid(name = index)
    conn.select_value("SELECT '#{name}'::regclass::oid")
  end

  it "creates a missing index" do
    expect(found).to be_nil
    build
    expect(found).to be_valid
  end

  it "leaves a valid index untouched" do
    build
    before_oid = oid
    build
    expect(found).to be_valid
    expect(oid).to eq(before_oid)
  end

  it "rebuilds an INVALID leftover from an interrupted build, as a valid one" do
    # a UNIQUE concurrent build over duplicate values fails and leaves INVALID
    expect { conn.execute("CREATE UNIQUE INDEX CONCURRENTLY #{index} ON cib_scratch (val)") }
      .to raise_error(ActiveRecord::RecordNotUnique)
    expect(found).not_to be_valid
    build
    expect(found).to be_valid
    expect(found.unique).to be(false)
  end

  it "raises on a valid index of that name with different columns, leaving it alone" do
    conn.add_index :cib_scratch, :id, name: index
    expect { build }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /index_cib_scratch_on_val.*\(id\).*\(val\)/)
    expect(found.columns).to eq(["id"])
  end

  it "raises on a valid index of that name with different uniqueness" do
    conn.execute("DELETE FROM cib_scratch")
    conn.add_index :cib_scratch, :val, name: index, unique: true
    expect { build }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /unique/)
  end

  it "builds a unique index when asked" do
    conn.execute("DELETE FROM cib_scratch")
    build(:val, unique: true)
    expect(found.unique).to be(true)
  end

  it "keeps a matching partial index and raises when the predicate differs" do
    build(:val, where: "val > 0")
    before_oid = oid
    build(:val, where: "val > 0")
    expect(oid).to eq(before_oid)
    expect { build(:val, where: "val > 5") }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /where/)
    expect { build(:val) }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch)
    expect(oid).to eq(before_oid)
  end

  it "raises when the access method differs" do
    build(:val, using: :btree)
    expect { build(:val, using: :hash) }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /hash/)
  end

  it "keeps an expression index on re-run instead of failing on it" do
    build("lower(txt)", name: index)
    before_oid = oid
    expect { build("lower(txt)", name: index) }.not_to raise_error
    expect(oid).to eq(before_oid)
    expect { build("upper(txt)", name: index) }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /lower/)
  end

  it "raises when the name is already used by an index on another table, and builds nothing" do
    conn.add_index :cib_other, :val, name: index
    expect { build }.to raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, /cib_other/)
    expect(found).to be_nil
  end

  it "passes the other add_index options on" do
    build(:val, include: :txt, comment: "scratch")
    expect(found.include).to eq(["txt"])
    expect(found.comment).to eq("scratch")
    expect { build(:val, include: :txt) }.not_to raise_error
  end

  it "refuses algorithm: and if_not_exists: from the caller" do
    expect { builder.add_index_concurrently(:cib_scratch, :val, algorithm: :default) }.to raise_error(ArgumentError, /algorithm/)
    expect { builder.add_index_concurrently(:cib_scratch, :val, if_not_exists: false) }.to raise_error(ArgumentError, /if_not_exists/)
  end

  it "works directly in a `change`: builds on up, removes (if present) on down" do
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      include ConcurrentIndexBuilder
      disable_ddl_transaction!
      def change = add_index_concurrently(:cib_scratch, :val)
    end
    run = ->(direction) { ActiveRecord::Migration.suppress_messages { migration.new.migrate(direction) } }
    run.call(:up)
    expect(found).to be_valid
    run.call(:down)
    expect(found).to be_nil
    expect { run.call(:down) }.not_to raise_error
  end
end
