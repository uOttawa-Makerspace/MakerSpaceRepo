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
            user.id,
            task.id,
            task.hours
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

  it "has no validations: negative, zero and orphan-task hours are valid and saved" do
    expect(VolunteerHour.new(user: user, volunteer_task_id: 0, total_time: -2)).to be_valid
    expect { VolunteerHour.create!(user: user, volunteer_task: task, total_time: -2) }.to change(VolunteerHour, :count).by(1)
  end

  it "defaults total_time to 0 and approval to nil" do
    hour = VolunteerHour.create!(user: user, volunteer_task: task)
    expect([hour.total_time, hour.approval]).to eq([0, nil])
  end

  it "rounds total_time to 2 decimals and raises RangeError beyond precision 9" do
    expect(VolunteerHour.create!(user: user, volunteer_task: task, total_time: 0.125).total_time).to eq(0.13)
    expect { VolunteerHour.create!(user: user, volunteer_task: task, total_time: 10**8) }.to raise_error(ActiveRecord::RangeError)
  end

  it "requires user_id and volunteer_task_id at the database level only" do
    expect { VolunteerHour.create!(volunteer_task: task) }.to raise_error(ActiveRecord::NotNullViolation)
    expect { VolunteerHour.create!(user: user) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "was_processed? is true for both approved and rejected" do
    expect(build(:volunteer_hour, :approved1).was_processed?).to be(true)
    expect(build(:volunteer_hour, :not_approved1).was_processed?).to be(true)
    expect(build(:volunteer_hour, :not_processed).was_processed?).to be(false)
  end

  describe ".create_volunteer_hour_from_approval(task_id, user_id, hours)" do
    it "creates an approved hour with the arguments in that order" do
      hour = VolunteerHour.create_volunteer_hour_from_approval(task.id, user.id, 4.5)
      expect(hour).to be_persisted
      expect(hour.attributes.values_at("volunteer_task_id", "user_id", "approval")).to eq([task.id, user.id, true])
      expect(hour.total_time).to eq(4.5)
    end

    it "raises NotNullViolation (not a soft failure) when the user id is missing" do
      expect { VolunteerHour.create_volunteer_hour_from_approval(task.id, nil, 1) }
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
