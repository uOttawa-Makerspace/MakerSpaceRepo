# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffExternalUnavailability, type: :model do
  it { should belong_to(:user) }
  it { should validate_presence_of(:ics_url) }

  it "accepts only http and https links on the default port, without a login" do
    user = create(:user, :staff)
    ["https://x.test/a.ics", "http://x.test/a.ics"].each do |url|
      expect(described_class.new(user: user, ics_url: url)).to be_valid
    end
    ["not a url", "file:///etc/passwd", "ftp://x.test/a.ics", "https://u:p@x.test/a.ics", "https://x.test:8080/a.ics", "https:///a.ics"].each do |url|
      expect(described_class.new(user: user, ics_url: url)).not_to be_valid, url
    end
  end

  it "is reachable from the user and removed with them is NOT cascaded (no dependent option)" do
    user = create(:user, :staff)
    record = described_class.create!(user: user, ics_url: "https://x.test/a.ics")
    expect(user.staff_external_unavailabilities).to eq([record])
  end
end
