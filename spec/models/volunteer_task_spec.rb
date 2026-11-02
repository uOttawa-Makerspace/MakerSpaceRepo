require "rails_helper"

RSpec.describe VolunteerTask, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end

    context "has_many" do
      it { should have_many(:volunteer_hours) }
      it { should have_many(:volunteer_task_joins) }
      it { should have_many(:require_trainings) }
      it { should have_many(:volunteer_task_requests) }
      it { should have_many(:cc_moneys) }
    end
  end

  describe "#delete_all_badge_requirements" do
    it "should delete all badge requirements" do
      task = create(:volunteer_task, :with_certifications)
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(2)
      VolunteerTask.find(task.id).delete_all_certifications
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(0)
    end
  end

  describe "#create_badge_requirements" do
    it "should create badge requirements" do
      task = create(:volunteer_task)
      training1 = create(:training)
      training2 = create(:training)
      VolunteerTask.find(task.id).create_certifications(
        [training1.id, training2.id]
      )
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(2)
    end
  end
end

# Chunk 13 characterization.
RSpec.describe VolunteerTask, "defaults, validation and cascade", type: :model do
  it "has column defaults and no presence validations" do
    task = VolunteerTask.create!
    expect(task.attributes.values_at("title", "description", "status", "joins", "category", "cc"))
      .to eq(["", "", "open", 1, "Other", 0])
    expect(task.hours).to eq(0)
  end

  it "accepts negative cc/hours/joins and arbitrary status" do
    task = VolunteerTask.new(cc: -1, hours: -2, joins: -3, status: "whatever")
    expect(task).to be_valid
  end

  it "is invalid with more than 5 photos" do
    task = create(:volunteer_task)
    6.times { Photo.new(volunteer_task: task).save(validate: false) }
    expect(task).not_to be_valid
    expect(task.errors[:photos]).to eq([" can't exceed 5 photos"])
  end

  it "is valid with exactly 5 photos" do
    task = create(:volunteer_task)
    5.times { Photo.new(volunteer_task: task).save(validate: false) }
    expect(task).to be_valid
  end

  it "destroy cascades to hours, joins, requests, CC money and photos but not require_trainings" do
    task = create(:volunteer_task, :with_certifications)
    create(:volunteer_hour, :approved1, volunteer_task: task)
    create(:volunteer_task_join, :active, volunteer_task: task)
    create(:volunteer_task_request, :approved, volunteer_task: task)
    create(:cc_money, volunteer_task: task)
    Photo.new(volunteer_task: task).save(validate: false)
    expect { task.destroy }.to change { [VolunteerHour, VolunteerTaskJoin, VolunteerTaskRequest, CcMoney, Photo].sum(&:count) }.by(-5)
    expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(2)
  end
end
