require "rails_helper"

RSpec.describe StaffAvailability, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user) }
      it { should belong_to(:user) }
    end
  end

  describe "Validations" do
    context "day" do
      it { should validate_presence_of(:day) }
    end

    context "start_time" do
      it { should validate_presence_of(:start_time) }
    end

    context "end_time" do
      it { should validate_presence_of(:end_time) }
    end
  end

  describe "week_day" do
    it "should get Monday" do
      staff_availability = create(:staff_availability)
      staff_availability.day = 1
      expect(staff_availability.week_day).to eq("Monday")
    end
  end
end
