# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261115130000_add_unique_index_to_spaces_lower_name")

# DDL is transactional in the test database, so each example drops the index first and the rollback restores the
# real schema afterwards.
RSpec.describe AddUniqueIndexToSpacesLowerName do
  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }

  before { conn.remove_index(:spaces, name: index, if_exists: true) }

  def found = conn.indexes(:spaces).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(name)
    now = Time.current
    conn.transaction(requires_new: true) do
      Space.insert_all!([{ name: name, created_at: now, updated_at: now }]).rows.flatten.first
    end
  end

  def rows = conn.select_rows("SELECT id, name FROM spaces ORDER BY id")

  it "refuses while two spaces share a name ignoring case, naming the ids, and changes nothing" do
    ids = [insert("Makerspace"), insert("MAKERSPACE")]
    insert("CEED")
    before_rows = rows

    expect { migrate }.to raise_error(described_class::DuplicatesFound, /"makerspace" -> ids #{ids.join(",")}\b/)
    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end

  context "on clean data" do
    before do
      insert("Makerspace")
      insert("CEED")
      insert(nil)
      migrate
    end

    it "builds a unique index on the lower-cased name" do
      expect(found).to have_attributes(unique: true, columns: "lower((name)::text)")
    end

    it "refuses the same name in another case and allows a new name and further unnamed rows" do
      expect { insert("makerSPACE") }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert("JMTS") }.not_to raise_error
      expect { insert(nil) }.not_to raise_error
    end

    it "removes the index on down, keeping every row" do
      before_rows = rows
      migrate(:down)
      expect(found).to be_nil
      expect(rows).to eq(before_rows)
    end

    it "is safe to run again" do
      expect { migrate }.not_to raise_error
      expect(found).to be_present
    end
  end
end
