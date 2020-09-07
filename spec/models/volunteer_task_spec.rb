require 'rails_helper'

RSpec.describe VolunteerTask, type: :model do
  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:user) }
      it { should belong_to(:space) }
    end

    context 'has_many' do
      it { should have_many(:volunteer_hours) }
      it { should have_many(:volunteer_task_joins) }
      it { should have_many(:require_trainings) }
      it { should have_many(:volunteer_task_requests) }
      it { should have_many(:cc_moneys) }
    end
  end

  describe "#delete_all_badge_requirements" do

    it 'should delete all badge requirements' do
      task = create(:volunteer_task, :with_certifications)
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(2)
      VolunteerTask.find(task.id).delete_all_certifications
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(0)
    end

  end

  describe "#create_badge_requirements" do

    it 'should create badge requirements' do
      task = create(:volunteer_task)
      training1 = create(:training)
      training2 = create(:training)
      VolunteerTask.find(task.id).create_certifications([training1.id, training2.id])
      expect(RequireTraining.where(volunteer_task_id: task.id).count).to eq(2)
    end

  end
end
