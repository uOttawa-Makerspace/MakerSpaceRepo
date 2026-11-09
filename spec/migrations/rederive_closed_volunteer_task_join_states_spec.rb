require "rails_helper"
require Rails.root.join("db/migrate/20261107220000_rederive_closed_volunteer_task_join_states")

# DDL is transactional in the test database, so the record table is dropped first and every example's changes
# roll back with it.
RSpec.describe RederiveClosedVolunteerTaskJoinStates do
  let(:connection) { ActiveRecord::Base.connection }
  let(:volunteer) { create(:user, :volunteer) }
  let(:task) { create(:volunteer_task) }
  let(:other_task) { create(:volunteer_task) }
  let(:closed_at) { Time.zone.parse("2026-03-01 12:00:00") }

  before { connection.drop_table :volunteer_task_join_state_changes, if_exists: true }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def join_for(user, task, active:, state: "joined", changed_at: nil, actor: nil)
    id = connection.select_value(<<~SQL.squish)
      INSERT INTO volunteer_task_joins (user_id, volunteer_task_id, active, state, state_changed_at, state_changed_by_id, created_at, updated_at)
      VALUES (#{user.id}, #{task.id}, #{active.nil? ? 'NULL' : active}, #{connection.quote(state)}, #{connection.quote(changed_at)},
              #{actor ? actor.id : 'NULL'}, #{connection.quote(closed_at - 3.days)}, #{connection.quote(closed_at)})
      RETURNING id
    SQL
    id.to_i
  end

  def request_for(user, task, approval)
    connection.execute(<<~SQL.squish)
      INSERT INTO volunteer_task_requests (user_id, volunteer_task_id, approval, created_at, updated_at)
      VALUES (#{user.id}, #{task.id}, #{approval.nil? ? 'NULL' : approval}, NOW(), NOW())
    SQL
  end

  def row(id)
    connection.select_one("SELECT state, state_changed_at, state_changed_by_id, active FROM volunteer_task_joins WHERE id = #{id}")
  end

  it "gives closed rows still marked joined the backfill state, and leaves every other row alone" do
    open_join = join_for(volunteer, task, active: true)
    drifted_done = join_for(volunteer, other_task, active: false)
    request_for(volunteer, other_task, true)
    other_user = create(:user, :volunteer)
    drifted_ended = join_for(other_user, task, active: false)
    request_for(other_user, task, false)
    drifted_unknown = join_for(create(:user, :volunteer), task, active: nil)
    already = join_for(volunteer, task, active: false, state: "left", changed_at: closed_at, actor: volunteer)
    migrate

    expect(row(open_join)).to include("state" => "joined", "state_changed_at" => nil, "active" => true)
    expect(row(drifted_done)).to include("state" => "completed", "state_changed_at" => closed_at, "state_changed_by_id" => nil, "active" => false)
    expect(row(drifted_ended)).to include("state" => "removed", "state_changed_at" => closed_at, "state_changed_by_id" => nil)
    expect(row(drifted_unknown)).to include("state" => "removed", "active" => nil)
    expect(row(already)).to include("state" => "left", "state_changed_by_id" => volunteer.id)
    expect(connection.select_value("SELECT count(*) FROM volunteer_task_joins WHERE (state = 'joined') <> (active IS TRUE)").to_i).to eq(0)
  end

  it "records each changed row and restores exactly those rows on rollback" do
    open_join = join_for(volunteer, task, active: true)
    drifted = join_for(volunteer, other_task, active: false)
    ended = join_for(create(:user, :volunteer), task, active: false, state: "completed", changed_at: closed_at)
    migrate

    expect(connection.select_rows("SELECT volunteer_task_join_id, old_state, new_state FROM volunteer_task_join_state_changes"))
      .to eq([[drifted, "joined", "removed"]])
    expect(row(drifted)["state"]).to eq("removed")

    migrate(:down)
    expect(row(drifted)).to include("state" => "joined", "state_changed_at" => nil, "active" => false)
    expect(row(open_join)["state"]).to eq("joined")
    expect(row(ended)).to include("state" => "completed", "state_changed_at" => closed_at)
    expect(connection.table_exists?(:volunteer_task_join_state_changes)).to be(true)
    expect(connection.select_value("SELECT count(*) FROM volunteer_task_join_state_changes WHERE restored_at IS NULL").to_i).to eq(0)
  end

  it "does not undo a row whose state or actor changed after the migration ran" do
    changed = join_for(volunteer, task, active: false)
    migrate
    actor = create(:user, :admin)
    connection.execute("UPDATE volunteer_task_joins SET state_changed_by_id = #{actor.id} WHERE id = #{changed}")

    migrate(:down)
    expect(row(changed)).to include("state" => "removed", "state_changed_by_id" => actor.id)
  end

  it "runs again after a rollback and records only rows that are drifted again" do
    first = join_for(volunteer, task, active: false)
    migrate
    migrate(:down)
    second = join_for(volunteer, other_task, active: false)
    migrate

    expect(connection.select_values("SELECT volunteer_task_join_id FROM volunteer_task_join_state_changes WHERE restored_at IS NULL"))
      .to contain_exactly(first, second)
    expect(row(first)["state"]).to eq("removed")
    expect(row(second)["state"]).to eq("removed")
  end
end
