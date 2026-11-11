# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261111110000_add_unique_index_to_pending_volunteer_hours")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToPendingVolunteerHours do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:task) { create(:volunteer_task) }
  let(:day) { Time.zone.parse("2026-03-04 00:00") }

  before { conn.execute("DROP INDEX IF EXISTS #{index}") }

  after do
    VolunteerHour.where(user_id: user.id).delete_all
    task.destroy
    Space.where(id: task.space_id).delete_all
    user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:volunteer_hours).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(approval: nil, total_time: 2.5, user_id: user.id)
    VolunteerHour.insert_all!([{ user_id: user_id, volunteer_task_id: task.id, date_of_task: day, total_time: total_time,
                                 approval: approval, created_at: Time.current, updated_at: Time.current }])
                 .rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM volunteer_hours WHERE user_id = #{user.id} ORDER BY id")

  it "refuses while identical pending hours exist, naming the ids, and changes nothing" do
    ids = [insert, insert]
    insert(approval: true)
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /user_id=#{user.id}.* -> ids #{ids.join(',')}\b/)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
  end

  context "on clean data" do
    before do
      insert
      insert(approval: true)
      insert(approval: true)
      migrate
    end

    it "builds a valid partial unique index on pending hours" do
      expect(found).to have_attributes(unique: true, where: "(approval IS NULL)")
      expect(found).to be_valid
    end

    it "refuses a second identical pending hour but allows reviewed, different and other users' hours" do
      expect { insert }.to raise_error(ActiveRecord::RecordNotUnique)
      expect { insert(total_time: 3) }.not_to raise_error
      expect { insert(approval: false) }.not_to raise_error
      other = create(:user)
      expect { insert(user_id: other.id) }.not_to raise_error
      VolunteerHour.where(user_id: other.id).delete_all
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
