# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteerTaskJoin, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
    end
  end

  describe "#scopes" do
    before(:each) do
      create(:volunteer_task_join, :active)
      create(:volunteer_task_join, :active)
      create(:volunteer_task_join, :not_active)
      create(:volunteer_task_join, :active_not_volunteer)
      create(:volunteer_task_join, :active_not_volunteer)
      create(:volunteer_task_join, :not_active_not_volunteer)
    end

    context "active" do
      it "should get the active joins" do
        expect(VolunteerTaskJoin.active.count).to eq(4)
      end
    end

    context "not_active" do
      it "should get the not active joins" do
        expect(VolunteerTaskJoin.not_active.count).to eq(2)
      end
    end

    context "user_type_volunteer" do
      it "should get the user type volunteer" do
        expect(VolunteerTaskJoin.user_type_volunteer.count).to eq(3)
      end
    end
  end
end

# Chunk 13 characterization.
RSpec.describe VolunteerTaskJoin, "defaults and uniqueness", type: :model do
  it "defaults to active and user_type Volunteer" do
    join = VolunteerTaskJoin.create!
    expect([join.active, join.user_type]).to eq([true, "Volunteer"])
  end

  it "allows the same user on the same task repeatedly (uniqueness validation is commented out)" do
    user = create(:user, :volunteer_with_volunteer_program)
    task = create(:volunteer_task)
    2.times { VolunteerTaskJoin.create!(user: user, volunteer_task: task) }
    expect(task.volunteer_task_joins.where(user: user).count).to eq(2)
  end

  it "scopes compose: active + user_type_volunteer ignores inactive and staff joins" do
    task = create(:volunteer_task)
    keep = create(:volunteer_task_join, :active, volunteer_task: task)
    create(:volunteer_task_join, :not_active, volunteer_task: task)
    create(:volunteer_task_join, :active_not_volunteer, volunteer_task: task)
    expect(task.volunteer_task_joins.active.user_type_volunteer).to eq([keep])
    expect(task.volunteer_task_joins.not_active.count).to eq(1)
  end
end

RSpec.describe VolunteerTaskJoin, "#finish!", type: :model do
  let(:staff) { create(:user, :staff) }
  let(:join) { create(:volunteer_task_join, :active) }

  it "defaults to joined, with no change time or actor" do
    expect(VolunteerTaskJoin.create!).to have_attributes(state: "joined", state_changed_at: nil, state_changed_by_id: nil)
  end

  %w[completed left removed].each do |ending|
    it "ends a joined row as #{ending} with the time and the actor, and clears active" do
      join.finish!(ending, by: staff)
      expect(join.reload).to have_attributes(state: ending, active: false, state_changed_by_id: staff.id)
      expect(join.state_changed_at).to be_within(1.minute).of(Time.current)
    end
  end

  it "ends a row once: a second ending is refused and changes nothing" do
    join.finish!(:completed, by: staff)
    expect { join.finish!(:removed, by: staff) }.to raise_error(VolunteerTaskJoin::NotJoined)
    expect(join.reload.state).to eq("completed")
  end

  it "refuses a stale copy of a row that has already ended" do
    stale = VolunteerTaskJoin.find(join.id)
    join.finish!(:left, by: join.user)
    expect { stale.finish!(:removed, by: staff) }.to raise_error(VolunteerTaskJoin::NotJoined)
    expect(join.reload.state).to eq("left")
  end

  it "refuses joined or an unknown state as an ending" do
    expect { join.finish!(:joined, by: staff) }.to raise_error(ArgumentError)
    expect { join.finish!(:gone, by: staff) }.to raise_error(ArgumentError)
    expect(join.reload.state).to eq("joined")
  end

  it "worked_on covers joined and completed rows only" do
    task = create(:volunteer_task)
    rows = %i[active completed left not_active].map { |trait| create(:volunteer_task_join, trait, volunteer_task: task) }
    expect(task.volunteer_task_joins.worked_on).to contain_exactly(rows[0], rows[1])
  end
end
