require "rails_helper"

RSpec.describe TimePeriod, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should have_many(:staff_availabilities) }
    end
  end
end
