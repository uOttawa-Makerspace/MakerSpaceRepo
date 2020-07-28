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
end
