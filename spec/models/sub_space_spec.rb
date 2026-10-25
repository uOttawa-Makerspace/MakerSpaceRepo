# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubSpace, type: :model do
  it { should belong_to(:space) }
  it { should have_many(:sub_space_bookings).dependent(:destroy) }

  it "requires a name with a custom message (copied from Space)" do
    record = SubSpace.new(space: create(:space), name: "")
    expect(record).not_to be_valid
    expect(record.errors[:name]).to eq(["A name is required for the space"])
  end

  it "defaults to automatic approval, private bookings and no limits" do
    record = SubSpace.create!(space: create(:space), name: "Room")
    expect(record).to have_attributes(
      approval_required: false, default_public: false, max_automatic_approval_hour: nil,
      maximum_booking_duration: nil, maximum_booking_hours_per_week: nil
    )
  end

  it "allows duplicate names within a space (no uniqueness)" do
    space = create(:space)
    SubSpace.create!(space: space, name: "Room")
    expect(SubSpace.new(space: space, name: "Room")).to be_valid
  end

  # WART(D-SP24): SubSpace#destroy with bookings raises InvalidForeignKey (dependent: :destroy removes the status before the booking row); the admin controller works around it with manual cleanup + delete.
  it "cannot be destroyed while it has bookings (FK violation)" do
    create(:booking_status, :pending)
    room = create(:sub_space)
    create(:sub_space_booking, sub_space: room)
    expect { room.destroy }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(SubSpaceBooking.count).to eq(1)
  end

  it "destroys when it has no bookings" do
    room = create(:sub_space)
    expect { room.destroy }.to change(SubSpace, :count).by(-1)
  end
end
