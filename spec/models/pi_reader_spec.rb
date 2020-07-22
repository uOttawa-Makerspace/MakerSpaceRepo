require 'rails_helper'

RSpec.describe PiReader, type: :model do
  describe 'Association' do
    context 'belongs_to' do
      it { should belong_to(:space) }
    end
  end

  describe 'Methods' do
    context "#pi_mac_with_location" do
      it 'should return mac address and location' do
        pi_reader = create(:pi_reader)
        pi_mac_address = pi_reader.pi_mac_address
        pi_location = pi_reader.pi_location
        expect(pi_reader.pi_mac_with_location).to eq("#{pi_mac_address} (#{pi_location})")
      end
    end
  end
end
