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

  it "shows just the mac for a card whose reader is not registered, and nothing for a card with no mac" do
    unknown = create(:rfid, mac_address: "de:ad:be:ef:00:01")
    no_mac = create(:rfid, mac_address: nil)
    labels = helper.rfid_options_list([unknown, no_mac], unknown.user).map(&:first)
    expect(labels[1]).to end_with(" - de:ad:be:ef:00:01")
    expect(labels[2]).to end_with("ago)")
  end
end
