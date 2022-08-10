require "rails_helper"

RSpec.describe StaffSpace, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user) }
      it { should belong_to(:space) }
    end
  end
end
