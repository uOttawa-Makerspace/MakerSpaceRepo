# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112200000_add_unique_index_to_staff_spaces_user_and_space")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToStaffSpacesUserAndSpace do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:space) { create(:space) }
  let!(:other_space) { create(:space) }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    StaffSpace.where(user_id: [user.id, other_user.id]).delete_all
    space.destroy
    other_space.destroy
    user.destroy
    other_user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:staff_spaces).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(user_id: user.id, space_id: space.id)
    now = Time.current
    StaffSpace.insert_all!([{ user_id: user_id, space_id: space_id, color: "#112233", created_at: now, updated_at: now }])
              .rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM staff_spaces WHERE user_id IN (#{user.id}, #{other_user.id}) ORDER BY id")

  it "refuses while a staff member is assigned to a space twice, naming the ids, and changes nothing" do
    ids = [insert, insert]
    insert(space_id: other_space.id)
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /user_id=#{user.id}, space_id=#{space.id} -> ids #{ids.join(",")}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end

  context "on clean data" do
    before do
      insert
      insert(space_id: other_space.id)
      insert(user_id: other_user.id)
      migrate
    end

    it "builds a valid unique index on user and space" do
      expect(found).to have_attributes(unique: true, columns: %w[user_id space_id])
      expect(found).to be_valid
    end

    it "refuses the same pair twice and allows another user or another space" do
      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert(user_id: other_user.id, space_id: other_space.id) }.not_to raise_error
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
