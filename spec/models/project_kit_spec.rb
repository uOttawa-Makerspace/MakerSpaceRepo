require "rails_helper"

RSpec.describe ProjectKit, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
  end

  describe "Validations" do
    it "needs a project that exists" do
      kit = build(:project_kit, proficient_project: nil, proficient_project_id: 0)
      expect(kit).not_to be_valid
      expect(kit.errors[:proficient_project]).to be_present
    end
  end
end
