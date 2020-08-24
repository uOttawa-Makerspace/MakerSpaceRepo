require 'rails_helper'

RSpec.describe PopularHour, type: :model do
  describe 'Methods' do
    context '#generate_data' do

      it 'should generate data' do
        create(:space)
        data = PopularHour.generate_data
        expect(data).to be_a(Hash)
      end

    end
  end
end
