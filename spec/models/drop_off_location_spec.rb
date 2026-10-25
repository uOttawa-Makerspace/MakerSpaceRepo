require "rails_helper"

RSpec.describe DropOffLocation, type: :model do
  describe "Association" do
    context "has_many" do
      it { should have_many(:proficient_projects) }
    end
  end

  it "has no validations (a blank name is valid)" do
    expect(DropOffLocation.new).to be_valid
  end
end
