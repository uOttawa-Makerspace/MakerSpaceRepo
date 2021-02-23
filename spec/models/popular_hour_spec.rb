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
        expect(popular_hours.count).to be(168 + 4)
      end

      it 'should return popular hour from space 2' do
        popular_hours = PopularHour.from_space(@space2.id)
        expect(popular_hours.count).to be(168 + 2)
      end
    end

    context "#get_popular_hours_per_period" do
      it 'should make populate the hash' do
        create(:space)
        hash = PopularHour.popular_hours_per_period(Date.today - 1.month, Date.today)
        expect(hash.length).to eq(Space.all.count)
        Space.all.each do |space|
          expect(hash[space.id].length).to eq(7)
          (0..6).each do |day|
            expect(hash[space.id][day].length).to eq(24)
          end
        end
      end
    end
  end
end
