require 'rails_helper'

RSpec.describe SpaceStaffHour, type: :model do

  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:space) }
    end
  end

  describe 'Validations' do

    context 'day' do
      it { should validate_presence_of(:day) }
    end

    context 'start_time' do
      it { should validate_presence_of(:start_time) }
    end

    context 'end_time' do
      it { should validate_presence_of(:end_time) }
    end

  end

  describe "week_day" do
    it 'should get Monday' do
      space_staff_hour = create(:space_staff_hour)
      space_staff_hour.day = 1
      expect(space_staff_hour.week_day).to eq("Monday")
    end
  end
end
