require "rails_helper"

# A10 round 3 item 6: reader lookups by the MAC stored on rfids/lab sessions are
# case/separator-insensitive (they used to be exact PiReader.find_by matches).
RSpec.describe Admin::UsersHelper, type: :helper do
  it "shows the location of a reader whose stored mac differs in case from the card's mac" do
    reader = create(:pi_reader, pi_location: "Bench 4")
    reader.update_column(:pi_mac_address, "AA:BB:CC:DD:EE:FF")
    rfid = create(:rfid, mac_address: "aa:bb:cc:dd:ee:ff")
    expect(helper.rfid_options_list([rfid], rfid.user).to_s).to include("Bench 4")
  end
end
