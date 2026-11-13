require "rails_helper"

RSpec.describe ProjectJoin, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:project_proposal).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Validations" do
    context "user_id" do
      it do
        create(:project_join, user: create(:user), project_proposal: create(:project_proposal))
        should validate_uniqueness_of(:user_id).scoped_to(:project_proposal_id)
      end
    end
  end
end
