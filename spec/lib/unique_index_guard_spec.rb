# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("lib/unique_index_guard")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper on
# its own scratch table, dropped after every example.
RSpec.describe UniqueIndexGuard do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { "index_uig_scratch_on_a_and_b" }
  let(:builder) do
    Class.new(ActiveRecord::Migration[8.1]) do
      include UniqueIndexGuard
      disable_ddl_transaction!
    end.new
  end

  before do
    conn.create_table(:uig_scratch, force: true) do |t|
      t.integer :a
      t.integer :b
      t.string :state
    end
  end

  after { conn.drop_table(:uig_scratch, if_exists: true) }

  def build(columns = %i[a b], **options)
    ActiveRecord::Migration.suppress_messages do
      builder.add_unique_index_concurrently(:uig_scratch, columns, name: index, **options)
    end
  end

  def found
    conn.indexes(:uig_scratch).find { |i| i.name == index }
  end

  it "builds a unique index when there are no duplicates" do
    conn.execute("INSERT INTO uig_scratch (a, b) VALUES (1, 1), (1, 2)")
    build
    expect(found).to have_attributes(unique: true, columns: %w[a b])
    expect(found).to be_valid
  end

  it "stops with the ids of the duplicates, builds nothing and removes nothing" do
    conn.execute("INSERT INTO uig_scratch (a, b) VALUES (1, 1), (1, 1), (2, 2)")
    ids = conn.select_values("SELECT id FROM uig_scratch WHERE a = 1 ORDER BY id")

    expect { build }.to raise_error(UniqueIndexGuard::DuplicatesFound, /a=1, b=1 -> ids #{ids.join(',')}/)

    expect(found).to be_nil
    expect(conn.select_value("SELECT count(*) FROM uig_scratch")).to eq(3)
  end

  it "does not count rows with a NULL in an index column" do
    conn.execute("INSERT INTO uig_scratch (a, b) VALUES (1, NULL), (1, NULL)")
    build
    expect(found).to be_valid
  end

  it "counts only the rows of a partial index" do
    conn.execute("INSERT INTO uig_scratch (a, b, state) VALUES (1, 1, 'done'), (1, 1, 'done'), (1, 1, 'open')")
    build(%i[a b], where: "state = 'open'")
    expect(found.where).to be_present
    expect { conn.execute("INSERT INTO uig_scratch (a, b, state) VALUES (1, 1, 'open')") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "keeps a valid index and rebuilds an invalid one" do
    build
    expect { build }.not_to raise_error
    conn.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{index}'::regclass")
    expect(found).not_to be_valid
    build
    expect(found).to be_valid
  end

  it "removes the index again" do
    build
    ActiveRecord::Migration.suppress_messages { builder.remove_unique_index_concurrently(:uig_scratch, name: index) }
    expect(found).to be_nil
  end
end
