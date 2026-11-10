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
  it "has column defaults when saved without validation" do
    task = VolunteerTask.new.tap { |t| t.save!(validate: false) }
    expect(task.attributes.values_at("title", "description", "status", "joins", "category", "cc"))
      .to eq(["", "", "open", 1, "Other", 0])
    expect(task.hours).to eq(0)
  end

  describe "form fields" do
    it "needs a title, whole CC of 0 or more, at least 1 seat and an open or completed status" do
      expect(build(:volunteer_task)).to be_valid
      expect(build(:volunteer_task, title: " ")).not_to be_valid
      expect(build(:volunteer_task, cc: -1)).not_to be_valid
      expect(build(:volunteer_task, cc: 1.5)).not_to be_valid
      expect(build(:volunteer_task, cc: 0)).to be_valid
      expect(build(:volunteer_task, joins: 0)).not_to be_valid
      expect(build(:volunteer_task, joins: -3)).not_to be_valid
      expect(build(:volunteer_task, status: "whatever")).not_to be_valid
      expect(build(:volunteer_task, status: "completed")).to be_valid
    end
  end

  describe "hours" do
    it "must be more than 0 on create and in the task form" do
      [0, -2, nil].each do |hours|
        expect(VolunteerTask.new(hours: hours)).not_to be_valid
        expect(VolunteerTask.new(hours: hours).tap { |t| t.valid?(:task_form) }.errors[:hours]).to be_present
      end
      expect(VolunteerTask.new(hours: 0.5, title: "Open house")).to be_valid
    end

    it "are not checked on a stored task with 0 or 36 hours outside the task form" do
      zero = VolunteerTask.new(hours: 0, title: "Old task").tap { |t| t.save!(validate: false) }
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

RSpec.describe VolunteerTask, "#remove_user", type: :model do
  let(:task) { create(:volunteer_task) }
  let(:user) { create(:user, :volunteer) }
  let(:staff) { create(:user, :staff) }

  it "marks the user's joined rows left when they remove themselves, and keeps every row" do
    first = create(:volunteer_task_join, :active, volunteer_task: task, user: user)
    # a stored duplicate from before joins were unique
    second = build(:volunteer_task_join, :active, volunteer_task: task, user: user).tap { |j| j.save!(validate: false) }

    expect(task.remove_user(user.id, by: user)).to be(true)
    rows = VolunteerTaskJoin.where(id: [first.id, second.id])
    expect(rows.pluck(:state, :active, :state_changed_by_id).uniq).to eq([["left", false, user.id]])
    expect(rows.map(&:state_changed_at)).to all(be_present)
  end

  it "marks the rows removed when someone else removes the user" do
    join = create(:volunteer_task_join, :active, volunteer_task: task, user: user)

    expect(task.remove_user(user.id, by: staff)).to be(true)
    expect(join.reload).to have_attributes(state: "removed", active: false, state_changed_by_id: staff.id)
  end

  it "leaves ended rows alone" do
    done = create(:volunteer_task_join, :completed, volunteer_task: task, user: user)
    create(:volunteer_task_join, :active, volunteer_task: task, user: user)

    expect { task.remove_user(user.id, by: staff) }.not_to(change { done.reload.attributes })
  end

  it "refuses, and writes nothing, when the join ended between the lookup and the change" do
    join = create(:volunteer_task_join, :active, volunteer_task: task, user: user)
    allow_any_instance_of(VolunteerTaskJoin).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      VolunteerTaskJoin.where(id: original.receiver.id).update_all(state: "left", active: false)
      original.call(*args, &block)
    end

    expect(task.remove_user(user.id, by: staff)).to be(false)
    expect(task.errors.full_messages).to eq(["The user to remove is not on this task."])
    expect(join.reload.state_changed_by_id).to be_nil
  end

  it "refuses a user with no joined row" do
    create(:volunteer_task_join, :not_active, volunteer_task: task, user: user)

    expect(task.remove_user(user.id, by: staff)).to be(false)
    expect(task.errors.full_messages).to eq(["The user to remove is not on this task."])
  end
end
