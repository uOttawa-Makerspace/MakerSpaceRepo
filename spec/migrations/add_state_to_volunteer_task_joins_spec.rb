require "rails_helper"
require Rails.root.join("db/migrate/20261107210000_add_state_to_volunteer_task_joins")

# DDL is transactional in the test database, so each example takes the new columns off first (down on the
# empty table) and the rollback restores the real schema afterwards.
RSpec.describe AddStateToVolunteerTaskJoins do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    migrate(:down)
    VolunteerTaskJoin.reset_column_information
  end

  after { VolunteerTaskJoin.reset_column_information }

  def migrate(direction = :up)
    ActiveRecord::Migration.suppress_messages { described_class.new.migrate(direction) }
  end

  def column?(name)
    connection.column_exists?(:volunteer_task_joins, name)
  end

  def join_for(user, task, active:, updated_at: 2.days.ago)
    now = Time.current
    id = connection.select_value(<<~SQL.squish)
      INSERT INTO volunteer_task_joins (user_id, volunteer_task_id, active, created_at, updated_at)
      VALUES (#{user.id}, #{task.id}, #{active.nil? ? 'NULL' : active}, #{connection.quote(now - 3.days)}, #{connection.quote(updated_at)})
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

  let(:volunteer) { create(:user, :volunteer) }
  let(:task) { create(:volunteer_task) }
  let(:other_task) { create(:volunteer_task) }

  it "copies each join's active flag into a state and leaves active alone" do
    closed_at = Time.zone.parse("2026-03-01 12:00:00")
    open_join = join_for(volunteer, task, active: true)
    done_join = join_for(volunteer, other_task, active: false, updated_at: closed_at)
    request_for(volunteer, other_task, true)
    other_user = create(:user, :volunteer)
    ended_join = join_for(other_user, task, active: false, updated_at: closed_at)
    request_for(other_user, task, false)
    unknown_join = join_for(create(:user, :volunteer), task, active: nil, updated_at: closed_at)
    migrate

    expect(row(open_join)).to include("state" => "joined", "state_changed_at" => nil, "active" => true)
    expect(row(done_join)).to include("state" => "completed", "state_changed_at" => closed_at, "active" => false)
    expect(row(ended_join)).to include("state" => "removed", "state_changed_at" => closed_at, "active" => false)
    expect(row(unknown_join)).to include("state" => "removed", "active" => nil)
    expect(connection.select_values("SELECT state_changed_by_id FROM volunteer_task_joins").compact).to be_empty
  end

  it "makes the database refuse a state outside the four values" do
    migrate
    id = join_for(volunteer, task, active: true)

    expect do
      connection.transaction(requires_new: true) { connection.execute("UPDATE volunteer_task_joins SET state = 'active' WHERE id = #{id}") }
    end.to raise_error(ActiveRecord::CheckViolation)
  end

  it "nullifies the actor when that user is deleted" do
    migrate
    actor = create(:user, :admin)
    id = join_for(volunteer, task, active: false)
    connection.execute("UPDATE volunteer_task_joins SET state = 'removed', state_changed_by_id = #{actor.id} WHERE id = #{id}")
    connection.execute("DELETE FROM users WHERE id = #{actor.id}")

    expect(row(id)).to include("state" => "removed", "state_changed_by_id" => nil)
  end

  it "rolls back to the old columns, keeps the old values, and runs again" do
    join_for(volunteer, task, active: true)
    join_for(volunteer, other_task, active: false)
    migrate
    before_rows = connection.select_rows("SELECT id, active FROM volunteer_task_joins ORDER BY id")
    migrate(:down)

    expect(%i[state state_changed_at state_changed_by_id].map { |c| column?(c) }).to eq([false, false, false])
    expect(connection.check_constraint_exists?(:volunteer_task_joins, name: described_class::CHECK_NAME)).to be(false)
    expect(connection.select_rows("SELECT id, active FROM volunteer_task_joins ORDER BY id")).to eq(before_rows)
    expect { migrate }.not_to raise_error
    expect(column?(:state)).to be(true)
  end

  it "refuses to roll back once a join has an actor or a state that disagrees with active" do
    actor = create(:user, :admin)
    id = join_for(volunteer, task, active: true)
    migrate
    connection.execute("UPDATE volunteer_task_joins SET state = 'left', state_changed_by_id = #{actor.id} WHERE id = #{id}")

    expect { migrate(:down) }.to raise_error(RuntimeError, /1 volunteer_task_joins row\(s\) have a recorded actor/)
    expect(column?(:state)).to be(true)

    connection.execute("UPDATE volunteer_task_joins SET state_changed_by_id = NULL WHERE id = #{id}")
    expect { migrate(:down) }.to raise_error(RuntimeError, /disagrees with active/)

    connection.execute("UPDATE volunteer_task_joins SET active = FALSE WHERE id = #{id}")
    expect { migrate(:down) }.not_to raise_error
  end
end
