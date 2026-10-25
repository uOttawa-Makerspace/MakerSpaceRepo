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
