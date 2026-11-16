require "rails_helper"

RSpec.describe Space, type: :model do
  describe "Association" do
    context "has_and_belongs_to_many" do
      it { should have_and_belong_to_many(:trainings) }
    end

    context "has_many" do
      it { should have_many(:pi_readers) }
      it { should have_many(:lab_sessions) }
      it { should have_many(:staff).through(:staff_spaces) }
      it { should have_many(:visitors).through(:lab_sessions) }
      it { should have_many(:training_sessions) }
      it { should have_many(:certifications) }
      it { should have_many(:volunteer_tasks) }
      it { should have_many(:popular_hours) }
      it { should have_many(:shadowing_hours) }
      it { should have_many(:users_with_current_space).class_name("User") }
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
        should validate_uniqueness_of(:name).case_insensitive.with_message(
                 "Space already exists"
               )
      end

      it "refuses a name that differs from another space's only in case" do
        create(:space, name: "Makerspace")
        space = Space.new(name: "MAKERSPACE")
        expect(space).not_to be_valid
        expect(space.errors[:name]).to eq(["Space already exists"])
      end

      it "has the database refuse a name repeated in another case" do
        create(:space, name: "Makerspace")
        now = Time.current
        expect { Space.insert_all!([{ name: "makerSPACE", created_at: now, updated_at: now }]) }
          .to raise_error(ActiveRecord::RecordNotUnique)
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

    context "#save_with_popular_hours" do
      it "saves the space and its 168 rows together" do
        space = Space.new(name: "Delta")
        expect { expect(space.save_with_popular_hours).to be(true) }.to change(PopularHour, :count).by(168)
        expect(space).to be_persisted
      end

      it "returns false and stores nothing for an invalid space" do
        expect { expect(Space.new(name: "").save_with_popular_hours).to be(false) }.not_to change { [Space.count, PopularHour.count] }
      end

      it "rolls the space back, reports and adds an error when the rows cannot be inserted" do
        allow(PopularHour).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "boom")
        space = Space.new(name: "Epsilon")
        expect(Rails.error).to receive(:report).with(instance_of(ActiveRecord::StatementInvalid), hash_including(handled: true))
        expect(space.save_with_popular_hours).to be(false)
        expect(Space.exists?(name: "Epsilon")).to be(false)
        expect(space.errors[:base]).not_to be_empty
      end
    end

    context "#create_popular_hours" do
      it "creates a row for every weekday and hour" do
        space = create(:space)
        expect { space.create_popular_hours }.to change { space.popular_hours.count }.from(0).to(168)
        expect(space.popular_hours.pluck(:day, :hour)).to match_array((0..6).to_a.product((0..23).to_a))
      end

      it "does nothing when the space already has its rows" do
        space = create(:space)
        space.create_popular_hours
        expect { space.create_popular_hours }.not_to change(PopularHour, :count)
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

    it "lists its staff, and the users who visited, through separate associations" do
      space = create(:space)
      staff = create(:user)
      visitor = create(:user)
      create(:staff_space, space: space, user: staff)
      create(:lab_session, space: space, user: visitor)

      expect(space.staff).to contain_exactly(staff)
      expect(space.visitors).to contain_exactly(visitor)
    end

    it "lists a visitor once however many sessions they had" do
      space = create(:space)
      visitor = create(:user)
      create(:lab_session, space: space, user: visitor)
      create(:lab_session, space: space, user: visitor)

      expect(space.visitors.to_a).to eq([visitor])
    end

    it "refuses destroy while a soft-deleted user still has it as their current space, and changes nothing" do
      space = create(:space)
      user = create(:user, space_id: space.id)
      user.update_columns(deleted: true)

      expect(space.destroy).to be(false)

      expect(space.errors.full_messages).to eq(["Cannot delete record because dependent users with current space exist"])
      expect(User.including_deleted.find(user.id).space_id).to eq(space.id)
    end

    it "refuses destroy while users still have it as their current space, and changes nothing" do
      space = create(:space)
      user = create(:user, space_id: space.id)

      expect(space.destroy).to be(false)

      expect(space.errors.full_messages).to eq(["Cannot delete record because dependent users with current space exist"])
      expect(Space.exists?(space.id)).to be(true)
      expect(user.reload.space_id).to eq(space.id)
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

    it "assigned_color_hex is the assigned colour as #rrggbb, and assigned_color_text is black or white for it" do
      texts = (0..9).map do |id|
        space = Space.new
        space.id = id
        [space.assigned_color_hex, space.assigned_color_text]
      end
      expect(texts.first).to eq(["#e6194b", "#000000"])
      expect(texts.to_h).to include("#ffe119" => "#000000", "#4363d8" => "#ffffff", "#46f0f0" => "#000000")
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

    it "does not create popular hours when a space is saved" do
      expect { create(:space) }.not_to change(PopularHour, :count)
    end
  end
end
