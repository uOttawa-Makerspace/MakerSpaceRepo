require 'rails_helper'

RSpec.describe PopularHour, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:space) }
    end
  end

  describe 'Methods' do
    before :all do
      @space1 = create(:space)
      @space2 = create(:space)
      4.times{ create(:popular_hour, space: @space1) }
      2.times{ create(:popular_hour, space: @space2) }
    end

    context '#from_space' do
      it 'should return popular hour from space 1' do
        popular_hours = PopularHour.from_space(@space1.id)
        expect(popular_hours.count).to be(4)
      end

      it 'should return popular hour from space 2' do
        popular_hours = PopularHour.from_space(@space2.id)
        expect(popular_hours.count).to be(2)
      end
    end
  end
end
