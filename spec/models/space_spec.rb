require "rails_helper"

RSpec.describe Space, type: :model do
  describe "Association" do
    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:trainings) }
    end

    context "has_many" do
      it { should have_many(:pi_readers) }
      it { should have_many(:lab_sessions) }
      it { should have_many(:users) }
      it { should have_many(:training_sessions) }
      it { should have_many(:certifications) }
      it { should have_many(:volunteer_tasks) }
      it { should have_many(:popular_hours) }
      it { should have_many(:shadowing_hours) }
      it { should have_many(:users) }
      it { should have_many(:staff_needed_calendars) }
    end
  end

  it "has associations that all resolve to a class" do
    expect { Space.reflect_on_all_associations.each(&:klass) }.not_to raise_error
  end

  describe "validation" do
    context "name" do
      it do
        should validate_presence_of(:name).with_message(
                 "A name is required for the space"
               )
      end
      it do
        should validate_uniqueness_of(:name).with_message(
                 "Space already exists"
               )
      end
    end
  end

  describe "methods" do
    context "#signed_in_users" do
      it "should show the signed in users" do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(
          user_id: user.id,
          space_id: space.id,
          sign_in_time: 1.hour.ago,
          sign_out_time: DateTime.now.tomorrow
        )
        expect(Space.last.signed_in_users.first).to eq(User.find(user.id))
      end

      it "never lists a soft-deleted user, even with a session still open" do
        user = create(:user, :regular_user)
        space = create(:space)
        create(:lab_session, user: user, space: space, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now)
        user.soft_delete!
        expect(space.signed_in_users).to be_empty
      end
    end

    context "#recently_signed_out_users" do
      it "is not emptied by an open session with no user" do
        user = create(:user, :regular_user)
        space = create(:space)
        create(:lab_session, user: user, space: space, sign_in_time: 1.day.ago, sign_out_time: 1.hour.ago)
        create(:lab_session, space: space, sign_in_time: 1.hour.ago, sign_out_time: 1.hour.from_now).update_columns(user_id: nil)
        expect(space.recently_signed_out_users).to eq([user])
      end

      it "never lists a soft-deleted user" do
        user = create(:user, :regular_user)
        space = create(:space)
        create(:lab_session, user: user, space: space, sign_in_time: 1.day.ago, sign_out_time: 1.hour.ago)
        user.soft_delete!
        expect(space.recently_signed_out_users).to be_empty
      end

      it "should get the recently signed out users" do
        user = create(:user, :regular_user)
        space = create(:space)
        LabSession.create(
          user_id: user.id,
          space_id: space.id,
          sign_in_time: 1.day.ago,
          sign_out_time: 1.hour.ago
        )
        expect(Space.last.recently_signed_out_users.first).to eq(
          User.find(user.id)
        )
      end
    end

    context "#after_create :create_popular_hours" do
      it "should create popular hours after creating space" do
        # Enable callback temporarily for this specific test
        Space.set_callback(:create, :after, :create_popular_hours)
        
        expect { create(:space) }.to change(PopularHour, :count).by(168)
        
        # Disable it again so other tests stay fast
        Space.skip_callback(:create, :after, :create_popular_hours)
      end
    end

    context "#makerspace?" do
      it "should return false" do
        space = create(:space, name: "MTC")
        expect(space.makerspace?).to eq(false)
      end

      it "should return true" do
        space = create(:space, name: "Makerspace")
        expect(space.makerspace?).to eq(true)
      end
    end

    context "#ceed?" do
      it "should return false" do
        space = create(:space, name: "MTC")
        expect(space.ceed?).to eq(false)
      end

      it "should return true" do
        space = create(:space, name: "CEED")
        expect(space.ceed?).to eq(true)
      end
    end
  end

  describe "characterization (chunk 14)" do
    include SpacesSpecHelpers
    include ActiveSupport::Testing::TimeHelpers

    it "validates name with custom messages (presence, uniqueness)" do
      create(:space, name: "Dup")
      blank = Space.new(name: "")
      expect(blank).not_to be_valid
      expect(blank.errors[:name]).to eq(["A name is required for the space"])
      dup = Space.new(name: "Dup")
      expect(dup).not_to be_valid
      expect(dup.errors[:name]).to eq(["Space already exists"])
    end

    it "refuses destroy with one message per kind of history, and deletes nothing" do
      space = create(:space)
      sub_space = create(:sub_space, space: space)
      create(:sub_space_booking, sub_space: sub_space)
      create(:volunteer_task, space: space)

      expect(space.destroy).to be(false)

      expect(space.errors.full_messages).to eq(
        ["Cannot delete record because dependent volunteer tasks exist",
         "Cannot delete record because dependent sub space bookings exist"]
      )
      expect(SubSpace.exists?(sub_space.id)).to be(true)
      expect(space.deletion_refusals.size).to eq(2)
    end

    it "words the refusals from the locale, with the association names of the locale" do
      space = create(:space)
      create(:volunteer_task, space: space)

      expect(I18n.with_locale(:fr) { space.deletion_refusals }).to eq(
        ["Impossible de supprimer l'enregistrement car il reste des tâches de bénévolat"]
      )
    end

    it "defaults keycode to a blank string and has no capacity limit" do
      space = Space.create!(name: "Defaults")
      expect(space).to have_attributes(keycode: "", max_capacity: nil, destroy_admin_id: nil)
    end

    it "identifies spaces by exact name" do
      expect(Space.new(name: "JMTS")).to be_jmts
      expect(Space.new(name: "jmts")).not_to be_jmts
      expect(Space.new(name: "Brunsfield Centre").needs_walk_in_safety_sheet?).to be(true)
      expect(Space.new(name: "MTC").needs_walk_in_safety_sheet?).to be(true)
      expect(Space.new(name: "Makerspace").needs_walk_in_safety_sheet?).to be(false)
    end

    it "assigned_color cycles through a 10-colour palette by id" do
      a = Space.new
      a.id = 3
      b = Space.new
      b.id = 13
      expect(a.assigned_color).to eq([67, 99, 216])
      expect(b.assigned_color).to eq(a.assigned_color)
    end

    it "destroys sub spaces, staff spaces, shifts, calendars and manager joins with the space" do
      space = create(:space)
      create(:sub_space, space: space)
      create(:staff_space, space: space)
      StaffNeededCalendar.create!(space: space, calendar_url: "https://x.test/a.ics")
      SpaceManagerJoin.create!(space: space, user: create(:user, :admin))
      expect { space.destroy }
        .to change(SubSpace, :count).by(-1).and change(StaffSpace, :count).by(-1)
        .and change(StaffNeededCalendar, :count).by(-1).and change(SpaceManagerJoin, :count).by(-1)
    end

    it "destroys a space that still has retired shift rows (FK shifts.space_id)" do
      space = create(:space)
      Shift.create!(space_id: space.id, start_datetime: 1.day.ago, end_datetime: 1.day.ago + 1.hour)
      expect { space.destroy }.to change(Shift, :count).by(-1)
    end

    it "does not create popular hours in the test environment (callback is skipped)" do
      expect { create(:space) }.not_to change(PopularHour, :count)
    end

    describe "#weekly_open_hours" do
      let(:space) { create(:space) }
      let(:url) { "https://cal.test/open.ics" }

      before { travel_to(Time.zone.local(2027, 3, 16, 12)) } # Tuesday, week of Sat 03-13 .. Fri 03-19
      after { travel_back }

      def open_calendar!
        StaffNeededCalendar.create!(space: space, calendar_url: url, role: "open_hours")
      end

      it "is empty without an open_hours calendar" do
        StaffNeededCalendar.create!(space: space, calendar_url: url)
        expect(space.weekly_open_hours).to eq([])
      end

      it "is empty when the feed cannot be fetched" do
        open_calendar!
        stub_ics(url, status: 500)
        expect(space.weekly_open_hours).to eq([])
      end

      it "lists single events inside the Saturday-to-Friday week in Toronto time, sorted" do
        open_calendar!
        stub_ics(url, body: ics_document(
          { uid: "late", summary: "Late", start: Time.utc(2027, 3, 16, 14), end: Time.utc(2027, 3, 16, 22) },
          { uid: "sat", summary: "Sat", start: Time.utc(2027, 3, 13, 15), end: Time.utc(2027, 3, 13, 20) },
          { uid: "before", summary: "Before", start: Time.utc(2027, 3, 12, 15), end: Time.utc(2027, 3, 12, 20) },
          { uid: "after", summary: "After", start: Time.utc(2027, 3, 20, 15), end: Time.utc(2027, 3, 20, 20) }
        ))
        rows = space.weekly_open_hours
        expect(rows.map(&:title)).to eq(%w[Sat Late])
        expect(rows.map { |r| [r.dtstart.iso8601, r.dtend.iso8601] }).to eq(
          [["2027-03-13T10:00:00-05:00", "2027-03-13T15:00:00-05:00"], ["2027-03-16T10:00:00-04:00", "2027-03-16T18:00:00-04:00"]]
        )
      end

      # parse_ics_calendar hands back RRULE as a String but weekly_open_hours reads it as a hash: any recurring event raises TypeError.
      it "raises TypeError when the feed contains a recurring event" do
        open_calendar!
        stub_ics(url, body: ics_document(uid: "r", summary: "Rec", start: Time.utc(2027, 3, 1, 14), end: Time.utc(2027, 3, 1, 22), rrule: "FREQ=WEEKLY;BYDAY=MO"))
        expect { space.weekly_open_hours }.to raise_error(TypeError)
      end
    end

    # parse_ics_calendar never returns the hash shape below (it gives the RRULE as a String), so these
    # examples hand the method the hash form it was written for.
    describe "#weekly_open_hours with an RRULE hash (feed parsing stubbed)" do
      let(:space) { create(:space) }

      before do
        travel_to(Time.zone.local(2027, 3, 16, 12)) # Tuesday, week of Sat 03-13 .. Fri 03-19
        StaffNeededCalendar.create!(space: space, calendar_url: "https://cal.test/open.ics", role: "open_hours")
      end

      after { travel_back }

      def feed(*events)
        allow(space).to receive(:parse_ics_calendar).and_return([{ id: "x", color: "#000", events: events }])
      end

      def times(rows)
        rows.map { |r| [r.title, r.dtstart.iso8601, r.dtend.iso8601] }
      end

      it "is empty when the parser returns nothing" do
        allow(space).to receive(:parse_ics_calendar).and_return([])
        expect(space.weekly_open_hours).to eq([])
      end

      it "skips events without a start" do
        feed({ title: "No start", start: nil, end: "2027-03-16T10:00:00" })
        expect(space.weekly_open_hours).to eq([])
      end

      it "ends an event at its end, else after its duration in ms, else one hour later" do
        feed({ title: "End", start: "2027-03-15T09:00:00", end: "2027-03-15T10:30:00" },
             { title: "Duration", start: "2027-03-16T09:00:00", duration: 7_200_000 },
             { title: "Plain", start: "2027-03-17T09:00:00" })
        expect(times(space.weekly_open_hours)).to eq(
          [["End", "2027-03-15T09:00:00-04:00", "2027-03-15T10:30:00-04:00"],
           ["Duration", "2027-03-16T09:00:00-04:00", "2027-03-16T11:00:00-04:00"],
           ["Plain", "2027-03-17T09:00:00-04:00", "2027-03-17T10:00:00-04:00"]]
        )
      end

      it "expands a weekly rule on its weekdays, leaving out exceptions, and keeps the week's occurrences only" do
        feed({ title: "Weekly", start: "2027-03-01T09:00:00", end: "2027-03-01T11:00:00",
               rrule: { freq: "weekly", byweekday: %w[mo we xx] }, exdate: ["2027-03-17T09:00:00", "not a date"] })
        expect(times(space.weekly_open_hours)).to eq([["Weekly", "2027-03-15T09:00:00-04:00", "2027-03-15T11:00:00-04:00"]])
      end

      it "expands daily, monthly and yearly rules, stopping at an until date or a count" do
        feed({ title: "Daily", start: "2027-03-01T09:00:00", end: "2027-03-01T10:00:00",
               rrule: { freq: "DAILY", until: "2027-03-14T23:00:00" } },
             { title: "Counted", start: "2027-03-13T09:00:00", end: "2027-03-13T10:00:00",
               rrule: { freq: "DAILY", count: 2 } },
             { title: "Monthly", start: "2027-02-17T09:00:00", end: "2027-02-17T10:00:00", rrule: { freq: "MONTHLY" } },
             { title: "Yearly", start: "2026-03-18T09:00:00", end: "2026-03-18T10:00:00", rrule: { freq: "YEARLY" } })
        expect(times(space.weekly_open_hours).map(&:first).tally).to eq("Daily" => 2, "Counted" => 2, "Monthly" => 1, "Yearly" => 1)
        daily = space.weekly_open_hours.select { |r| r.title == "Daily" }
        expect(daily.map { |r| r.dtstart.to_date.to_s }).to eq(["2027-03-13", "2027-03-14"])
      end

      it "skips a rule with an unknown or missing frequency" do
        feed({ title: "Hourly", start: "2027-03-16T09:00:00", end: "2027-03-16T10:00:00", rrule: { freq: "HOURLY" } },
             { title: "None", start: "2027-03-16T09:00:00", end: "2027-03-16T10:00:00", rrule: { byweekday: ["mo"] } })
        expect(space.weekly_open_hours).to eq([])
      end

      it "ignores a weekday list without a known day" do
        feed({ title: "Odd", start: "2027-03-16T09:00:00", end: "2027-03-16T10:00:00",
               rrule: { freq: "WEEKLY", byweekday: ["xx"] } })
        expect(space.weekly_open_hours.map(&:title)).to eq(["Odd"])
      end

      it "falls back to the event length when an occurrence has no end time" do
        occurrence = double("occurrence", start_time: Time.zone.local(2027, 3, 16, 9))
        allow(occurrence).to receive(:end_time).and_raise(StandardError)
        schedule = instance_double(IceCube::Schedule, add_recurrence_rule: nil, occurrences_between: [occurrence])
        allow(IceCube::Schedule).to receive(:new).and_return(schedule)
        feed({ title: "Odd", start: "2027-03-16T09:00:00", end: "2027-03-16T10:15:00", rrule: { freq: "DAILY" } })
        expect(times(space.weekly_open_hours)).to eq([["Odd", "2027-03-16T09:00:00-04:00", "2027-03-16T10:15:00-04:00"]])
      end
    end
  end
end
