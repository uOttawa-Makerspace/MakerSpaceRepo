require 'rails_helper'

RSpec.describe ProjectJoin, type: :model do
  describe 'Association' do

    context 'belongs_to' do
      it { should belong_to(:project_proposal) }
      it { should belong_to(:user) }
    end

  end

  describe "Validations" do

    context "user_id" do
      it { should validate_uniqueness_of(:user_id).scoped_to(:project_proposal_id) }
    end

  end
end
