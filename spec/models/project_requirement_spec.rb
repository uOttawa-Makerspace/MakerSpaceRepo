require 'rails_helper'

RSpec.describe ProjectRequirement, type: :model do

  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:proficient_project) }
      it { should belong_to(:required_project) }
    end
  end

  describe 'Validations' do
    context "user" do
      it { should validate_uniqueness_of(:proficient_project_id).scoped_to(:required_project_id).with_message('This project is already a pre-requisite') }
    end
  end

end
