require "rails_helper"

RSpec.describe ProjectKit, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
    end
  end
end
