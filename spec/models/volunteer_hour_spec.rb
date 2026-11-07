# frozen_string_literal: true

require "rails_helper"

RSpec.describe VolunteerHour, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:user).without_validating_presence }
      it { should belong_to(:volunteer_task).without_validating_presence }
    end
  end

  describe "#scopes" do
    before(:each) do
      create(:volunteer_hour, :approved1)
      create(:volunteer_hour, :approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_approved1)
      create(:volunteer_hour, :not_processed)
    end

    context "approved" do
      it "should get the approved hours" do
        expect(VolunteerHour.approved.count).to eq(2)
      end
    end

    context "rejected" do
      it "should get the rejected hours" do
        expect(VolunteerHour.rejected.count).to eq(3)
      end
    end

    context "not_processed" do
      it "should get the not_processed hours" do
        expect(VolunteerHour.not_processed.count).to eq(1)
      end
    end

    context "processed" do
      it "should get the processed hours" do
        expect(VolunteerHour.processed.count).to eq(5)
      end
    end
  end

  describe "model methods" do
    context "#was_approved?" do
      it "should be processed" do
        create(:volunteer_hour, :not_approved1)
        expect(VolunteerHour.last.was_processed?).to be_truthy
      end

      it "should not be processed" do
        create(:volunteer_hour, :not_processed)
        expect(VolunteerHour.last.was_processed?).to be_falsey
      end
    end

    context "#create_volunteer_hour_from_approval" do
      it "should create volunteer hour" do
        user = create(:user, :volunteer_with_volunteer_program)
        task = create(:volunteer_task)
        expect {
          VolunteerHour.create_volunteer_hour_from_approval(
            task.id,
            user.id,
            task.hours,
            Time.zone.parse("2026-03-02 10:00")
          )
        }.to change(VolunteerHour, :count).by(1)
      end
    end
  end
end

# Chunk 13 characterization.
RSpec.describe VolunteerHour, "state and defaults", type: :model do
  let(:user) { create(:user, :volunteer_with_volunteer_program) }
  let(:task) { create(:volunteer_task) }

  describe "hand-logged hours (save_hand_logged)" do
    def attrs(overrides = {})
      { volunteer_task_id: task.id, date_of_task: Date.current, total_time: 2 }.merge(overrides)
    end

    it "saves hours above 0 and up to 24 on a past or current day" do
      expect(VolunteerHour.new(user: user).save_hand_logged(attrs(total_time: 24))).to be(true)
      expect(VolunteerHour.new(user: user).save_hand_logged(attrs(total_time: 0.01, date_of_task: 3.days.ago))).to be(true)
    end

    it "refuses 0, negative, over 24 and missing hours" do
      [0, -1, 24.01, nil].each do |hours|
        hour = VolunteerHour.new(user: user)
        expect(hour.save_hand_logged(attrs(total_time: hours))).to be(false)
        expect(hour.errors[:total_time]).to be_present
      end
    end

    it "refuses a date after today" do
      hour = VolunteerHour.new(user: user)
      expect(hour.save_hand_logged(attrs(date_of_task: Date.current + 1))).to be(false)
      expect(hour.errors[:date_of_task]).to eq(["cannot be in the future"])
    end

    it "checks each field only when it changes, so a stored 36 hour or 0 hour approved row stays editable" do
      [36, 0].each do |stored|
        row = create(:volunteer_hour, user: user, volunteer_task: task, approval: true, total_time: stored, date_of_task: 5.days.ago)
        reloaded = VolunteerHour.find(row.id)
        expect(reloaded.total_time).to eq(stored)
        expect(reloaded.save_hand_logged(date_of_task: 4.days.ago, approval: false)).to be(true)
        expect(reloaded.reload.total_time).to eq(stored)
        expect(reloaded.save_hand_logged(total_time: 25)).to be(false)
      end
    end

    it "leaves a stored future date alone while other fields change" do
      row = VolunteerHour.new(user: user, volunteer_task: task, total_time: 1, date_of_task: Date.current + 30)
      row.save!
      expect(VolunteerHour.find(row.id).save_hand_logged(total_time: 2)).to be(true)
    end
  end

  it "saves in the default context without the hand-logged limits (awards take the task's hours)" do
    expect(VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 36, Time.current)).to be_persisted
    expect(VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 0, Time.current)).to be_persisted
  end

  it "requires a volunteer task that exists but the default context does not limit total_time: negative hours are saved" do
    expect(VolunteerHour.new(user: user, volunteer_task_id: 0, total_time: -2)).not_to be_valid
    expect { VolunteerHour.create!(user: user, volunteer_task: task, total_time: -2, date_of_task: Date.current) }.to change(VolunteerHour, :count).by(1)
  end

  it "defaults total_time to 0 and approval to nil" do
    hour = VolunteerHour.create!(user: user, volunteer_task: task, date_of_task: Date.current)
    expect([hour.total_time, hour.approval]).to eq([0, nil])
  end

  it "rounds total_time to 2 decimals and raises RangeError beyond precision 9" do
    expect(VolunteerHour.create!(user: user, volunteer_task: task, total_time: 0.125, date_of_task: Date.current).total_time).to eq(0.13)
    expect { VolunteerHour.create!(user: user, volunteer_task: task, total_time: 10**8, date_of_task: Date.current) }.to raise_error(ActiveRecord::RangeError)
  end

  it "requires a volunteer task in the model and a user at the database level only" do
    expect { VolunteerHour.create!(volunteer_task: task, date_of_task: Date.current) }.to raise_error(ActiveRecord::NotNullViolation)
    expect { VolunteerHour.create!(user: user, date_of_task: Date.current) }.to raise_error(ActiveRecord::RecordInvalid, /Volunteer task/)
  end

  it "requires date_of_task" do
    hour = build(:volunteer_hour, date_of_task: nil)
    expect(hour).not_to be_valid
    expect(hour.errors[:date_of_task]).to be_present
    expect(build(:volunteer_hour, date_of_task: Date.current)).to be_valid
  end

  it "was_processed? is true for both approved and rejected" do
    expect(build(:volunteer_hour, :approved1).was_processed?).to be(true)
    expect(build(:volunteer_hour, :not_approved1).was_processed?).to be(true)
    expect(build(:volunteer_hour, :not_processed).was_processed?).to be(false)
  end

  describe ".create_volunteer_hour_from_approval(task_id, user_id, hours, date)" do
    it "creates an approved hour with the arguments in that order" do
      hour = VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 4.5, Time.current)
      expect(hour).to be_persisted
      expect(hour.attributes.values_at("volunteer_task_id", "user_id", "approval")).to eq([task.id, user.id, true])
      expect(hour.total_time).to eq(4.5)
    end

    it "dates the hour with the date it is given" do
      worked = Time.zone.parse("2026-01-15 09:30")
      hour = VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 1, worked)
      expect(hour.reload.date_of_task).to eq(worked)
    end

    it "does not create an hour without a date" do
      expect { VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 1, nil) }
        .not_to change(VolunteerHour, :count)
    end

    it "raises NotNullViolation (not a soft failure) when the user id is missing" do
      expect { VolunteerHour.create_volunteer_hour_from_approval(task.id, nil, 1, Time.current) }
        .to raise_error(ActiveRecord::NotNullViolation)
    end
  end

  it "feeds User#get_total_hours from approved hours only" do
    create(:volunteer_hour, :approved1, user: user)
    create(:volunteer_hour, :not_processed, user: user)
    create(:volunteer_hour, :not_approved1, user: user)
    expect(user.get_total_hours).to eq(10)
  end
end
