# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving. The same user joins the same task twice at the same moment.
# The first inserts its row and parks before committing; the second passes the uniqueness validation (it cannot see
# the uncommitted row), so its insert waits on the unique index. Once the first commits, the second must report the
# same error as a failed validation instead of raising.
RSpec.describe VolunteerTaskJoin, "uniqueness under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:task) { create(:volunteer_task, joins: 3) }

  after do
    VolunteerTaskJoin.where(user_id: volunteer.id).delete_all
    task.destroy
    Space.where(id: task.space_id).delete_all
    User.unscoped.where(id: volunteer.id).destroy_all
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  def joined_rows = VolunteerTaskJoin.joined.where(user_id: volunteer.id, volunteer_task_id: task.id)

  it "stores one joined row and gives the loser the already-on-this-task error" do
    parked = Queue.new
    resume = Queue.new
    one = in_thread do
      VolunteerTaskJoin.transaction do
        VolunteerTaskJoin.create!(user: volunteer, volunteer_task: task, user_type: "Volunteer")
        parked << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
    end
    ThreadPause.await(parked)
    loser = VolunteerTaskJoin.new(user: volunteer, volunteer_task: task, user_type: "Volunteer")
    two = in_thread { [loser.save, loser.errors.full_messages] }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    expect(one.value).not_to be_a(StandardError)
    saved, messages = two.value
    expect(saved).to be(false)
    expect(messages).to eq(["User is already on this task"])
    expect(joined_rows.count).to eq(1)
  end

  it "leaves an enclosing transaction usable after losing the race" do
    create(:volunteer_task_join, volunteer_task: task, user: volunteer, state: "joined")
    loser = VolunteerTaskJoin.new(user: volunteer, volunteer_task: task, user_type: "Volunteer")

    VolunteerTaskJoin.transaction do
      expect(loser.save(validate: false)).to be(false)
      expect(loser.errors.full_messages).to eq(["User is already on this task"])
      expect(joined_rows.count).to eq(1)
    end
  end

  it "makes a task form that adds an already-joined user fail with that message and add nothing" do
    create(:volunteer_task_join, volunteer_task: task, user: volunteer, state: "joined", user_type: "Volunteer")
    allow_any_instance_of(VolunteerTaskJoin).to receive(:valid?).and_return(true)
    editor = create(:user, :staff)

    expect(task.update_from_form({}, by: editor, joins: { add_volunteers: [volunteer.id] })).to be(false)
    expect(task.errors.full_messages).to eq(["User is already on this task"])
    expect(joined_rows.count).to eq(1)
  ensure
    User.unscoped.where(id: editor&.id).destroy_all
  end
end
