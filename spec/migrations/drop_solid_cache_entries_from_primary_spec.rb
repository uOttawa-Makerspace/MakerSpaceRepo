require "rails_helper"
require Rails.root.join("db/migrate/20261115100000_drop_solid_cache_entries_from_primary")
require Rails.root.join("db/migrate/20261031000002_create_solid_cache_entries")

# PostgreSQL schema changes are transactional, so every example (the table it creates and drops included) is
# rolled back, and the test database keeps the schema it had before.
RSpec.describe DropSolidCacheEntriesFromPrimary do
  let(:connection) { ActiveRecord::Base.connection }

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { described_class.new.public_send(direction) }
  end

  def columns
    connection.columns(:solid_cache_entries).to_h { |c| [c.name, [c.sql_type, c.limit, c.null]] }
  end

  def indexes
    connection.indexes(:solid_cache_entries).map { |i| [i.columns, i.unique] }
  end

  it "starts from a primary database without the table" do
    expect(connection.table_exists?(:solid_cache_entries)).to be(false)
  end

  it "goes down to the empty table with its columns and indexes" do
    migrate(:down)

    # PostgreSQL keeps no length for bytea, so the key and value limits are not stored.
    expect(columns).to eq(
      "id" => ["bigint", 8, false],
      "key" => ["bytea", nil, false],
      "value" => ["bytea", nil, false],
      "created_at" => ["timestamp(6) without time zone", nil, false],
      "key_hash" => ["bigint", 8, false],
      "byte_size" => ["integer", 4, false]
    )
    expect(indexes).to contain_exactly([["byte_size"], false], [%w[key_hash byte_size], false], [["key_hash"], true])
    expect(connection.select_value("SELECT COUNT(*) FROM solid_cache_entries").to_i).to eq(0)
  end

  it "goes down to the same table the create migration built" do
    ActiveRecord::Migration.suppress_messages { CreateSolidCacheEntries.new.migrate(:up) }
    created = [columns, indexes]
    migrate(:up)

    migrate(:down)

    expect([columns, indexes]).to eq(created)
  end

  it "goes up again, removing the table" do
    migrate(:down)
    connection.execute(<<~SQL.squish)
      INSERT INTO solid_cache_entries (key, value, created_at, key_hash, byte_size)
      VALUES ('k', 'v', now(), 1, 2)
    SQL

    migrate(:up)

    expect(connection.table_exists?(:solid_cache_entries)).to be(false)
  end
end
