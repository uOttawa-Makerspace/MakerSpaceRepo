require "rails_helper"

RSpec.describe StaffSpace, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:space).without_validating_presence }
    end
  end
end
