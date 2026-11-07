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
  it "has column defaults and no presence validations once saved" do
    task = VolunteerTask.new.tap { |t| t.save!(validate: false) }
    expect(task.attributes.values_at("title", "description", "status", "joins", "category", "cc"))
      .to eq(["", "", "open", 1, "Other", 0])
    expect(task.hours).to eq(0)
  end

  it "accepts negative cc/joins and arbitrary status" do
    task = VolunteerTask.new(cc: -1, hours: 2, joins: -3, status: "whatever")
    expect(task).to be_valid
  end

  describe "hours" do
    it "must be more than 0 on create and in the task form" do
      [0, -2, nil].each do |hours|
        expect(VolunteerTask.new(hours: hours)).not_to be_valid
        expect(VolunteerTask.new(hours: hours).tap { |t| t.valid?(:task_form) }.errors[:hours]).to be_present
      end
      expect(VolunteerTask.new(hours: 0.5)).to be_valid
    end

    it "are not checked on a stored task with 0 or 36 hours outside the task form" do
      zero = VolunteerTask.new(hours: 0).tap { |t| t.save!(validate: false) }
      long = create(:volunteer_task, hours: 36)
      expect(zero.update(status: "completed")).to be(true)
      expect(long.update(title: "renamed")).to be(true)
      expect(long.valid?(:task_form)).to be(true)
      expect(zero.valid?(:task_form)).to be(false)
    end
  end

  describe "deletion once hours or CC were awarded" do
    let(:task) { create(:volunteer_task) }

    it "is allowed when nothing is awarded, even with pending and rejected hours" do
      create(:volunteer_hour, :not_processed, volunteer_task: task)
      create(:volunteer_hour, :not_approved1, volunteer_task: task)
      create(:volunteer_task_join, :active, volunteer_task: task)
      expect(task.awarded?).to be(false)
      expect { task.destroy }.to change(VolunteerTask, :count).by(-1)
    end

    it "is refused while an approved hour row exists, and nothing is removed" do
      create(:volunteer_hour, :approved1, volunteer_task: task)
      create(:volunteer_task_join, :active, volunteer_task: task)
      task.create_certifications([create(:training).id])
      expect(task.awarded?).to be(true)
      expect { expect(task.destroy).to be(false) }.not_to change { [VolunteerTask, VolunteerHour, VolunteerTaskJoin, RequireTraining].map(&:count) }
      expect(task.errors[:base]).to eq(["This task has approved hours or CC awarded and cannot be deleted."])
    end

    it "is refused while a CC money row exists, even for 0 CC" do
      create(:cc_money, volunteer_task: task, cc: 0)
      expect(task.awarded?).to be(true)
      expect { expect(task.destroy).to be(false) }.not_to change { [VolunteerTask, CcMoney].map(&:count) }
    end
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

  it "destroy cascades to hours, joins, requests, photos and require_trainings when nothing was awarded" do
    task = create(:volunteer_task, :with_certifications)
    create(:volunteer_hour, :not_processed, volunteer_task: task)
    create(:volunteer_task_join, :active, volunteer_task: task)
    create(:volunteer_task_request, :approved, volunteer_task: task)
    Photo.new(volunteer_task: task).save(validate: false)
    expect { task.destroy }.to change { [VolunteerHour, VolunteerTaskJoin, VolunteerTaskRequest, Photo].sum(&:count) }.by(-4)
    expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(0)
  end
end
