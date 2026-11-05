require "rails_helper"

RSpec.describe StaffAvailability, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:user).without_validating_presence }
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

  describe "characterization (chunk 14)" do
    let(:period) { create(:time_period) }

    it "requires a time period" do
      record = StaffAvailability.new(recurring: true, day: "1", start_time: "09:00", end_time: "10:00")
      expect(record).not_to be_valid
      expect(record.errors[:time_period]).to include("must exist")
      expect(record.errors[:time_period_id]).to eq(["This field is required."])
    end

    it "recurring records need day, start_time and end_time but not datetimes" do
      record = StaffAvailability.new(time_period: period, recurring: true)
      expect(record).not_to be_valid
      expect(record.errors.attribute_names).to contain_exactly(:day, :start_time, :end_time)
      record.assign_attributes(day: "1", start_time: "09:00", end_time: "10:00")
      expect(record).to be_valid
    end

    it "one-off records need start_datetime and end_datetime but not day/times" do
      record = StaffAvailability.new(time_period: period, recurring: false)
      expect(record).not_to be_valid
      expect(record.errors.attribute_names).to contain_exactly(:start_datetime, :end_datetime)
      record.assign_attributes(start_datetime: Time.zone.local(2027, 3, 1, 9), end_datetime: Time.zone.local(2027, 3, 1, 10))
      expect(record).to be_valid
    end

    it "does not require a user" do
      expect(StaffAvailability.new(time_period: period, recurring: false, start_datetime: 1.hour.ago, end_datetime: Time.zone.now)).to be_valid
    end

    it "week_day maps day 0-6 to names, a blank day to Sunday and 7 to nil" do
      expect(StaffAvailability.new(day: "0").week_day).to eq("Sunday")
      expect(StaffAvailability.new(day: "6").week_day).to eq("Saturday")
      expect(StaffAvailability.new(day: nil).week_day).to eq("Sunday")
      expect(StaffAvailability.new(day: "7").week_day).to be_nil
    end

    it "stores time-of-day columns without a date" do
      record = StaffAvailability.create!(time_period: period, day: "2", start_time: "09:30", end_time: "17:00")
      expect(record.reload.start_time.strftime("%H:%M")).to eq("09:30")
      expect(record.end_time.strftime("%H:%M")).to eq("17:00")
    end

    describe "exceptions" do
      let(:record) { StaffAvailability.create!(time_period: period, day: "1", start_time: "09:00", end_time: "10:00") }

      it "are created through nested attributes and destroyed with the availability" do
        record.update!(exceptions_attributes: [{ covers: "all_after", start_at: Time.zone.local(2027, 3, 15, 9) }])
        expect(record.exceptions.map(&:covers)).to eq(["all_after"])
        expect { record.destroy }.to change(StaffAvailabilityException, :count).by(-1)
      end

      it "default to one_time and require start_at" do
        exception = StaffAvailabilityException.new(staff_availability: record)
        expect(exception.covers).to eq("one_time")
        expect(exception).not_to be_valid
        expect(exception.errors.attribute_names).to eq([:start_at])
        expect(StaffAvailabilityException.covers.keys).to eq(%w[one_time all_after])
      end
    end
  end
end
