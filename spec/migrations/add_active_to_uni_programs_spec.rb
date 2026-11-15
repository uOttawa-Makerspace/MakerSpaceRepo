# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112160000_add_active_to_uni_programs")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It takes the column and index away to recreate the table as it was before, and puts them back afterwards. The
# example that stops on duplicates leaves the column without the index, so `after` always runs the (repeatable) `up`.
RSpec.describe AddActiveToUniPrograms do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let(:marker) { "Migration spec program" }

  before { migrate(:down) }

  after do
    conn.execute("DELETE FROM uni_programs WHERE program = #{conn.quote(marker)}")
    migrate(:up)
  end

  def column? = conn.column_exists?(:uni_programs, :active)

  def found = conn.indexes(:uni_programs).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
    PooledStatements.reset
  end

  def insert(department: "Computing", faculty: "Engineering")
    conn.execute("INSERT INTO uni_programs (program, level, faculty, department) " \
                 "VALUES (#{conn.quote(marker)}, 'Master''s', #{conn.quote(faculty)}, #{conn.quote(department)})")
  end

  def stored = conn.select_rows("SELECT program, level, faculty, department FROM uni_programs " \
                                "WHERE program = #{conn.quote(marker)} ORDER BY department, faculty")

  def flags = conn.select_values("SELECT active FROM uni_programs WHERE program = #{conn.quote(marker)}")

  it "adds the column with every existing row active and builds a valid unique partial index" do
    insert
    insert(faculty: "Science")
    migrate

    expect(flags).to eq([true, true])
    expect(found).to have_attributes(unique: true, columns: %w[program level faculty], where: "active")
    expect(found).to be_valid
  end

  it "marks the second copy of a row identical in every column inactive, keeping both rows" do
    insert
    insert
    before = stored
    migrate

    expect(stored).to eq(before)
    expect(flags).to contain_exactly(true, false)
  end

  it "stops, changing no row, when the same program has two different departments" do
    insert
    insert(department: "Other")
    before = stored

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /program=#{marker}, level=Master's, faculty=Engineering/)

    expect(found).to be_nil
    expect(stored).to eq(before)
  end

  it "is safe to run again" do
    insert
    migrate
    expect { migrate }.not_to raise_error
    expect(flags).to eq([true])
  end

  it "removes the column and index on down, keeping every row" do
    insert
    insert
    migrate
    before = stored
    migrate(:down)

    expect(column?).to be(false)
    expect(found).to be_nil
    expect(stored).to eq(before)
  end
end
