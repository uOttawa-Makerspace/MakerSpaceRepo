# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffExternalUnavailability, type: :model do
  it { should belong_to(:user) }
  it { should validate_presence_of(:ics_url) }

  it "does not validate the url format" do
    record = described_class.new(user: create(:user, :staff), ics_url: "not a url")
    expect(record).to be_valid
  end

  it "is reachable from the user and removed with them is NOT cascaded (no dependent option)" do
    user = create(:user, :staff)
    record = described_class.create!(user: user, ics_url: "https://x.test/a.ics")
    expect(user.staff_external_unavailabilities).to eq([record])
  end
end
