# frozen_string_literal: true

require "rails_helper"

# Live updates of the staff dashboard tables. The signed-in rows of a space that asks for a
# walk-in safety sheet say which users have not signed one.
RSpec.describe StaffDashboardChannel do
  include_context "with test cable adapter"
  include TableQueries
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2027, 3, 12, 12)) { example.run } }

  let!(:space) { create(:space, name: "MTC") }
  let(:stream) { StaffDashboardChannel.table_stream(space.id, :en) }

  before do
    signed = create(:user, :regular_user)
    create(:walk_in_safety_sheet, :is_adult, user: signed, space: space)
    [signed, create(:user, :regular_user), create(:user, :regular_user)].each do |user|
      create(:lab_session, user: user, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
    end
    gone = create(:user, :regular_user)
    create(:lab_session, user: gone, space: space, sign_in_time: 3.hours.ago, sign_out_time: 1.hour.ago)
  end

  def expect_rows_for_three_signed_in_users
    have_broadcasted_to(stream).from_channel(Turbo::StreamsChannel).with do |html|
      expect(html.scan("data-user-id=").size).to eq(4) # three signed in, one recently signed out
      expect(html.scan("Did not sign sheet").size).to eq(2)
    end
  end

  it "renders every signed-in row, with the missing-sheet marker, when the tables are broadcast" do
    expect { described_class.broadcast_table_updates(space.id) }.to expect_rows_for_three_signed_in_users
  end

  it "renders the tables once per language, each to that language's stream" do
    english = have_broadcasted_to(stream).from_channel(Turbo::StreamsChannel).with do |html|
      expect(html).to include("Did not sign sheet", "3 users inside MTC")
      expect(html).not_to include("N'a pas signé la fiche")
    end
    french = have_broadcasted_to(described_class.table_stream(space.id, :fr)).from_channel(Turbo::StreamsChannel).with do |html|
      expect(html).to include("N&#39;a pas signé la fiche", "3 utilisateurs dans MTC")
      expect(html).not_to include("Did not sign sheet")
    end

    expect { described_class.broadcast_table_updates(space.id) }.to english.and(french)
  end

  it "reads the walk-in sheets of all signed-in users in one query" do
    sheet_reads = selects_on("walk_in_safety_sheets") { described_class.broadcast_table_updates(space.id) }

    expect(sheet_reads.size).to eq(1)
  end

  it "sends the tap-in modal for the user without touching the tables" do
    user = create(:user, :regular_user)

    expect { described_class.send_tap_in(user, space.id) }
      .to have_broadcasted_to("space_event_#{space.id}").with(a_hash_including("add_user" => a_hash_including("id" => user.id)))
    expect { described_class.send_tap_in(user, space.id) }
      .not_to have_broadcasted_to(StaffDashboardChannel.table_stream(space.id, :en)).from_channel(Turbo::StreamsChannel)
  end

  it "broadcasts the same tables when a user is tapped out" do
    expect { described_class.send_tap_out(create(:user, :regular_user), space.id) }.to expect_rows_for_three_signed_in_users
  end

  # The broadcast is rendered outside any request, so the profile links must not carry a host.
  it "links each row to the user's profile by a relative path" do
    usernames = LabSession.where(space: space).joins(:user).pluck("users.username")
    links = have_broadcasted_to(stream).from_channel(Turbo::StreamsChannel).with do |html|
      hrefs = Nokogiri::HTML.fragment(html).css("tr[data-user-id] td:first-child a").map { |a| a["href"] }
      expect(hrefs).to match_array(usernames.map { |username| "/#{username}" })
      expect(html).not_to include("example.org")
    end

    expect { described_class.broadcast_table_updates(space.id) }.to links
  end

  describe "subscribing to a space's tap-in events" do
    let(:assigned) { create(:user, :staff).tap { |u| StaffSpace.create!(user: u, space: space) } }

    def subscribe_as(user, space_id)
      stub_connection current_user: user
      subscribe(space_id: space_id)
    end

    it "streams the space's events to staff assigned to it" do
      subscribe_as(assigned, space.id)
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("space_event_#{space.id}")
    end

    it "streams any space's events to staff who are not assigned to it" do
      subscribe_as(create(:user, :staff), space.id)
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("space_event_#{space.id}")
    end

    it "rejects an unknown or missing space, and a regular user" do
      subscribe_as(assigned, 0)
      expect(subscription).to be_rejected
      subscribe_as(assigned, nil)
      expect(subscription).to be_rejected
      subscribe_as(create(:user, :regular_user), space.id)
      expect(subscription).to be_rejected
    end

    it "lets an admin follow any space" do
      subscribe_as(create(:user, :admin), space.id)
      expect(subscription).to be_confirmed
    end
  end
end
