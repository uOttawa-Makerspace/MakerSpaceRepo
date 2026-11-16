# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261111100000_add_unique_index_to_programs_user_and_type")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToProgramsUserAndType do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    Program.where(user_id: user.id).delete_all
    user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:programs).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(type, user_id: user.id)
    Program.insert_all!([{ user_id: user_id, program_type: type, created_at: Time.current, updated_at: Time.current }])
           .rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM programs WHERE user_id = #{user.id} ORDER BY id")

  it "refuses while a user holds a program twice, naming the ids, and changes nothing" do
    ids = [insert(Program::VOLUNTEER), insert(Program::VOLUNTEER)]
    other = insert(Program::DEV_PROGRAM)
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /user_id=#{user.id}, program_type=Volunteer Program -> ids #{ids.join(',')}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(rows.map(&:first)).to include(other)
  end

  context "on clean data" do
    before do
      insert(Program::VOLUNTEER)
      insert(Program::DEV_PROGRAM)
      migrate
    end

    it "builds a valid unique index on user and program type" do
      expect(found).to have_attributes(unique: true, columns: %w[user_id program_type])
      expect(found).to be_valid
    end

    it "refuses the same program twice for one user and allows it for another user" do
      expect { insert(Program::VOLUNTEER) }.to raise_error(ActiveRecord::RecordNotUnique)
      other = create(:user)
      expect { insert(Program::VOLUNTEER, user_id: other.id) }.not_to raise_error
      Program.where(user_id: other.id).delete_all
      other.destroy
    end

    it "removes the index on down, keeping every row" do
      before_rows = rows
      migrate(:down)
      expect(found).to be_nil
      expect(rows).to eq(before_rows)
    end

    it "is safe to run again" do
      expect { migrate }.not_to raise_error
      expect(found).to be_valid
    end
  end
end
