require "rails_helper"

RSpec.describe Shift, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:space).without_validating_presence }
    end

    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:users) }
    end
  end

  describe "Validations" do
    context "start_datetime" do
      it { should validate_presence_of(:start_datetime) }
    end

    context "end_datetime" do
      it { should validate_presence_of(:end_datetime) }
    end
  end

  describe "Methods" do
    context "event_title" do
      it "should return the title of the shift" do
        user = create(:user, name: "John Doe")
        shift = create(:shift, users: [user], reason: "Test Reason")
        expect(shift.return_event_title).to eq("Test Reason for John Doe")
      end
    end

    context "color" do
      it "should return color for single user" do
        staff_space = create(:staff_space)
        StaffSpace.find(staff_space.id).update(color: "#0099ff")
        shift =
          create(:shift, users: [staff_space.user], space: staff_space.space)
        expect(shift.color(staff_space.space_id, 1)).to eq(
          "rgba(0, 153, 255, 1)"
        )
      end

      it "should return color for single user but transparent" do
        staff_space = create(:staff_space)
        StaffSpace.find(staff_space.id).update(color: "#0099ff")
        shift =
          create(:shift, users: [staff_space.user], space: staff_space.space)
        expect(shift.color(staff_space.space_id, 0.7)).to eq(
          "rgba(0, 153, 255, 0.7)"
        )
      end

      it "should return color for multi user" do
        space = create(:space)
        staff_space1 = create(:staff_space, space: space)
        StaffSpace.find(staff_space1.id).update(color: "#000000")
        staff_space2 = create(:staff_space, space: space)
        StaffSpace.find(staff_space2.id).update(color: "#ffffff")
        shift =
          create(
            :shift,
            users: [staff_space1.user, staff_space2.user],
            space: space
          )
        expect(shift.color(space.id, 1)).to eq(
          "linear-gradient(to right, rgba(0, 0, 0, 1) 0% 50%, rgba(255, 255, 255, 1) 50% 100%)"
        )
      end
    end
  end

  describe "Google calendar sync (HTTP stubbed at the boundary)" do
    include ActiveSupport::Testing::TimeHelpers

    let(:json) { { "Content-Type" => "application/json" } }
    let(:events_url) { %r{googleapis\.com/calendar/v3/calendars/[^/]+/events\z|googleapis\.com/calendar/v3/calendars/[^/]+/events\?} }
    let(:event_url) { %r{googleapis\.com/calendar/v3/calendars/[^/]+/events/gid1} }

    before do
      stub_request(:post, "https://www.googleapis.com/oauth2/v4/token")
        .to_return(status: 200, body: { access_token: "t", expires_in: 3600, token_type: "Bearer" }.to_json, headers: json)
      stub_request(:post, events_url).to_return(status: 200, body: { id: "gid1" }.to_json, headers: json)
      stub_request(:get, event_url).to_return(status: 200, body: { id: "gid1" }.to_json, headers: json)
      stub_request(:put, event_url).to_return(status: 200, body: { id: "gid1" }.to_json, headers: json)
      stub_request(:delete, event_url).to_return(status: 204)
    end

    it "defaults to pending and never calls Google while pending" do
      shift = create(:shift)
      expect(shift.pending).to be(true)
      expect(shift.google_event_id).to be_nil
      expect(a_request(:any, /googleapis/)).not_to have_been_made
    end

    it "creates a Google event when saved as not pending and stores its id" do
      shift = create(:shift, pending: false)
      expect(shift.google_event_id).to eq("gid1")
      expect(a_request(:post, events_url)).to have_been_made.once
    end

    it "uses the fixed test calendar id in the test environment" do
      expect(Shift.return_space_calendar(create(:space))).to eq("c_hbktsseobsqd92u5rufsjbcok8@group.calendar.google.com")
    end

    # WART(D-SP21): update_event subtracts utc_offset from the shift's own datetimes, so every save of a synced shift moves it later (+4h in summer, +5h in winter).
    it "shifts start/end later by the UTC offset on every save of a synced shift" do
      { Time.zone.local(2027, 7, 6, 9) => 4.hours, Time.zone.local(2027, 1, 12, 9) => 5.hours }.each do |start, drift|
        shift = create(:shift, pending: false, start_datetime: start, end_datetime: start + 1.hour)
        shift.update!(reason: "edited")
        expect(shift.reload.start_datetime - start).to eq(drift)
        expect(shift.end_datetime - (start + 1.hour)).to eq(drift)
      end
    end

    it "deletes the Google event when a synced shift is destroyed" do
      shift = create(:shift, pending: false)
      shift.destroy
      expect(a_request(:delete, event_url)).to have_been_made.once
    end

    it "does not call Google when destroying a shift that was never synced" do
      create(:shift).destroy
      expect(a_request(:delete, /googleapis/)).not_to have_been_made
    end

    # WART(D-SP22): a failed Google insert returns the string "error", and `.id` on it raises NoMethodError: the shift is not saved.
    it "raises NoMethodError and does not save when Google rejects the insert" do
      stub_request(:post, events_url).to_return(status: 500, body: "{}", headers: json)
      shift = build(:shift, pending: false)
      expect { shift.save }.to raise_error(NoMethodError, /undefined method 'id'/)
      expect(Shift.count).to eq(0)
    end

    # WART(D-SP23): Shift#color raises NoMethodError for a user with no StaffSpace in that space.
    it "color raises when a user has no StaffSpace for the space" do
      shift = create(:shift)
      expect { shift.color(shift.space_id, 1) }.to raise_error(NoMethodError)
    end
  end
end
