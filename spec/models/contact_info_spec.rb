require "rails_helper"

RSpec.describe ContactInfo, type: :model do
  describe "Association" do
    context "has_one" do
      it { should have_many(:opening_hours) }
    end
  end
end
