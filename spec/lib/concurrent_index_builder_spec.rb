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
      t.integer :num
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
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(:cib_scratch, columns, name: index, **options) }
  end

  def found(table = :cib_scratch, name = index)
    conn.indexes(table).find { |i| i.name == name }
  end

  def oid(name = index)
    conn.select_value("SELECT '#{name}'::regclass::oid")
  end

  def mismatch(pattern = nil)
    raise_error(ConcurrentIndexBuilder::IndexDefinitionMismatch, *pattern)
  end

  it "builds a missing index" do
    expect(found).to be_nil
    build
    expect(found).to be_valid
    expect(found.columns).to eq(["val"])
    expect(found.unique).to be(false)
  end

  it "builds a unique index when asked" do
    conn.execute("DELETE FROM cib_scratch")
    build(:val, unique: true)
    expect(found.unique).to be(true)
  end

  it "keeps a valid plain index that matches, same oid" do
    build(%i[val num])
    before_oid = oid
    build(%i[val num])
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

  describe "a valid index of that name that is not the requested plain one" do
    it "raises for a partial index" do
      conn.add_index :cib_scratch, :val, name: index, where: "val > 0"
      expect { build }.to mismatch(/where \(val > 0\)/)
    end

    it "raises for an index with include" do
      conn.add_index :cib_scratch, :val, name: index, include: :txt
      expect { build }.to mismatch(/include \(txt\)/)
    end

    it "raises for an expression index" do
      conn.execute("CREATE INDEX #{index} ON cib_scratch (lower(txt))")
      expect { build }.to mismatch(/expression/)
    end

    it "raises for a descending order" do
      conn.add_index :cib_scratch, :val, name: index, order: { val: :desc }
      expect { build }.to mismatch(/order/)
    end

    it "raises for an opclass" do
      conn.add_index :cib_scratch, :txt, name: index, opclass: :text_pattern_ops
      expect { build(:txt) }.to mismatch(/opclass/)
    end

    it "raises when it is unique and the request is not, and the reverse" do
      conn.execute("DELETE FROM cib_scratch")
      conn.add_index :cib_scratch, :val, name: index, unique: true
      expect { build }.to mismatch(/unique/)
      conn.remove_index :cib_scratch, name: index
      conn.add_index :cib_scratch, :val, name: index
      expect { build(:val, unique: true) }.to mismatch(/not the requested unique/)
    end

    it "raises for other columns, or the same columns in another order" do
      conn.add_index :cib_scratch, :id, name: index
      expect { build }.to mismatch(/\(id\).*\(val\)/)
      conn.remove_index :cib_scratch, name: index
      conn.add_index :cib_scratch, %i[num val], name: index
      expect { build(%i[val num]) }.to mismatch
    end

    it "raises for another access method" do
      conn.execute("CREATE INDEX #{index} ON cib_scratch USING hash (val)")
      expect { build }.to mismatch(/hash/)
    end
  end

  it "raises when the name is used by an index on another table, and builds nothing" do
    conn.add_index :cib_other, :val, name: index
    expect { build }.to mismatch(/cib_other/)
    expect(found).to be_nil
  end

  it "raises when the name is the table's primary-key index, which indexes() does not list" do
    expect { ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(:cib_scratch, :id, name: "cib_scratch_pkey") } }
      .to mismatch(/relkind i/)
  end

  it "keeps a matching index when the table is given schema-qualified" do
    qualified = "public.cib_scratch"
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(qualified, :val, name: index) }
    before_oid = oid
    ActiveRecord::Migration.suppress_messages { builder.add_index_concurrently(qualified, :val, name: index) }
    expect(oid).to eq(before_oid)
  end

  it "raises for a column collation, which IndexDefinition does not report" do
    default = conn.select_value("SELECT datcollate FROM pg_database WHERE datname = current_database()")
    other = default == "C" ? "POSIX" : "C"
    conn.execute(%(CREATE INDEX #{index} ON cib_scratch (txt COLLATE "#{other}")))
    expect { build(:txt) }.to mismatch(/default collations/)
  end

  it "raises when the name is used by a sequence" do
    conn.execute("CREATE SEQUENCE #{index}")
    expect { build }.to mismatch(/relkind S/)
    expect(found).to be_nil
  ensure
    conn.execute("DROP SEQUENCE IF EXISTS #{index}")
  end

  it "raises ArgumentError for any other keyword" do
    expect { builder.add_index_concurrently(:cib_scratch, :val, name: index, where: "val > 0") }.to raise_error(ArgumentError)
    expect { builder.add_index_concurrently(:cib_scratch, :val, name: index, algorithm: :default) }.to raise_error(ArgumentError)
    expect { builder.add_index_concurrently(:cib_scratch, :val, name: index, if_not_exists: false) }.to raise_error(ArgumentError)
    expect { builder.add_index_concurrently(:cib_scratch, :val) }.to raise_error(ArgumentError)
  end

  it "raises ArgumentError when reverting" do
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      include ConcurrentIndexBuilder
      disable_ddl_transaction!
      def change = add_index_concurrently(:cib_scratch, :val, name: "index_cib_scratch_on_val")
    end
    expect { ActiveRecord::Migration.suppress_messages { migration.new.migrate(:down) } }.to raise_error(ArgumentError, /reverted/)
    expect(found).to be_nil
  end
end
