# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112230000_add_single_row_index_to_design_days")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create a second row, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddSingleRowIndexToDesignDays do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }

  before do
    conn.execute("DROP INDEX IF EXISTS #{index}")
    DesignDay.unscoped.delete_all
  end

  after do
    DesignDay.unscoped.delete_all
    migrate(:up) unless found
  end

  def found = conn.indexes(:design_days).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert = DesignDay.insert_all!([{ day: Date.new(2026, 5, 5), sheet_key: "", is_live: false }]).rows.flatten.first

  it "refuses while more than one row exists, naming the ids, and changes nothing" do
    ids = [insert, insert]

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /ids #{ids.join(',')}\z/)

    expect(found).to be_nil
    expect(DesignDay.unscoped.order(:id).pluck(:id)).to eq(ids)
  end

  it "builds a valid unique index with one row, or none, and then refuses a second row" do
    insert
    migrate

    expect(found).to be_valid
    expect(found).to have_attributes(unique: true)
    expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(DesignDay.unscoped.count).to eq(1)
  end

  it "builds on an empty table, is safe to run again, and down keeps the row" do
    migrate
    expect { migrate }.not_to raise_error
    insert
    migrate(:down)

    expect(found).to be_nil
    expect(DesignDay.unscoped.count).to eq(1)
  end
end
