# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261112180000_add_unique_index_to_volunteer_task_joins_joined_user_and_task")

# CREATE INDEX CONCURRENTLY cannot run in a transaction, so this spec runs outside the transactional wrapper.
# It drops the index to create duplicates, rebuilds it afterwards and removes the rows it made.
RSpec.describe AddUniqueIndexToVolunteerTaskJoinsJoinedUserAndTask do
  self.use_transactional_tests = false

  let(:conn) { ActiveRecord::Base.connection }
  let(:index) { described_class::INDEX_NAME }
  let!(:user) { create(:user) }
  let!(:other_user) { create(:user) }
  let!(:task) { create(:volunteer_task) }
  let!(:other_task) { create(:volunteer_task) }
  let(:t0) { Time.zone.parse("2026-03-11 04:00:00") }

  before do
    conn.execute("DROP INDEX IF EXISTS #{index}")
    conn.execute("DELETE FROM volunteer_task_join_duplicate_endings")
  end

  after do
    VolunteerTaskJoin.where(user_id: [user.id, other_user.id]).delete_all
    conn.execute("DELETE FROM volunteer_task_join_duplicate_endings")
    task.destroy
    other_task.destroy
    Space.where(id: [task.space_id, other_task.space_id]).delete_all
    user.destroy
    other_user.destroy
    migrate(:up) unless found
  end

  def found = conn.indexes(:volunteer_task_joins).find { |i| i.name == index }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def insert(task, user, state: "joined", created_at: t0, changed_by: nil, changed_at: nil)
    VolunteerTaskJoin.insert_all!([{ volunteer_task_id: task.id, user_id: user.id, state: state, active: state == "joined",
                                     state_changed_at: changed_at, state_changed_by_id: changed_by&.id,
                                     created_at: created_at, updated_at: created_at }]).rows.flatten.first
  end

  def rows = conn.select_rows("SELECT * FROM volunteer_task_joins WHERE user_id IN (#{user.id}, #{other_user.id}) ORDER BY id")
  def row(id) = conn.select_one("SELECT state, active, state_changed_at, state_changed_by_id, updated_at FROM volunteer_task_joins WHERE id = #{id}")
  def records = conn.select_rows("SELECT volunteer_task_join_id, kept_join_id, old_state, new_state, restored_at IS NOT NULL FROM volunteer_task_join_duplicate_endings")

  it "ends the newer of two joined rows, keeps both rows, records the old state and builds the index" do
    older = insert(task, user, created_at: t0)
    newer = insert(task, user, created_at: t0 + 3.seconds)
    history = [insert(task, user, state: "left", changed_at: t0, changed_by: user), insert(task, user, state: "completed")]
    other = insert(other_task, user)
    untouched = history.map { |id| row(id) } + [row(older), row(other)]
    count = rows.size

    migrate

    expect(found).to be_present
    expect(found.unique).to be(true)
    expect(rows.size).to eq(count)
    expect(row(newer)).to include("state" => "removed", "active" => false, "state_changed_by_id" => nil)
    expect(row(newer)["state_changed_at"]).to be_present
    expect(history.map { |id| row(id) } + [row(older), row(other)]).to eq(untouched)
    expect(records).to eq([[newer, older, "joined", "removed", false]])
  end

  it "takes the later id when both rows were made at the same moment" do
    first = insert(task, user)
    second = insert(task, user)
    migrate
    expect([row(first)["state"], row(second)["state"]]).to eq(%w[joined removed])
  end

  it "refuses and changes nothing when more than the one pair of two is joined twice, naming the ids" do
    pair = [insert(task, user), insert(task, user)]
    other_pair = [insert(other_task, user), insert(other_task, user)]
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /ids #{pair.join(",")}\n.*ids #{other_pair.join(",")}/m)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(records).to be_empty
  end

  it "refuses and changes nothing when a pair is joined three times" do
    ids = Array.new(3) { insert(task, user) }
    before_rows = rows

    expect { migrate }.to raise_error(UniqueIndexGuard::DuplicatesFound, /ids #{ids.join(",")}/)
    expect(rows).to eq(before_rows)
  end

  it "leaves repeated ended rows alone and changes nothing when there is no joined duplicate" do
    insert(task, user, state: "left")
    insert(task, user, state: "left")
    insert(task, user)
    before_rows = rows

    migrate

    expect(found).to be_present
    expect(rows).to eq(before_rows)
    expect(records).to be_empty
  end

  it "is safe to run twice" do
    insert(task, user)
    newer = insert(task, user, created_at: t0 + 1.second)
    migrate
    after_first = rows
    migrate
    expect(rows).to eq(after_first)
    expect(records.size).to eq(1)
    expect(row(newer)["state"]).to eq("removed")
  end

  it "down drops the index and restores the ended row exactly, then keeps the record" do
    insert(task, user)
    newer = insert(task, user, created_at: t0 + 1.second)
    before_rows = rows
    migrate

    migrate(:down)

    expect(found).to be_nil
    expect(rows).to eq(before_rows)
    expect(records).to eq([[newer, rows.first.first, "joined", "removed", true]])
  end

  it "down leaves a row alone that was changed again after the migration" do
    insert(task, user)
    newer = insert(task, user, created_at: t0 + 1.second)
    migrate
    conn.execute("UPDATE volunteer_task_joins SET state = 'left' WHERE id = #{newer}")

    migrate(:down)

    expect(row(newer)["state"]).to eq("left")
  end

  it "the index refuses a second joined row but allows repeated ended rows" do
    migrate
    insert(task, user)
    expect { insert(task, user) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert(task, user, state: "left") }.not_to raise_error
    expect { insert(task, user, state: "left") }.not_to raise_error
  end
end
