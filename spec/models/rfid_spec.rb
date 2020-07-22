require 'rails_helper'

RSpec.describe Rfid, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:user) }
    end
  end

  describe 'Validations' do
    context "card_number" do
      it { should validate_presence_of(:card_number).with_message('Card number is required.') }
      it { should validate_uniqueness_of(:card_number).with_message('Card number is already in use.') }
    end
  end

  describe 'Scopes' do
    before(:each) do
      3.times{ create(:rfid, user: nil) }
      2.times{ create(:rfid) }
    end

    context '#recent_unset' do
      it 'should return rfid with nil users' do
        expect(Rfid.recent_unset.count).to eq(3)
      end
    end
  end
end
