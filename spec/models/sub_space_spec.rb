# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubSpace, type: :model do
  it { should belong_to(:space) }
  it { should have_many(:sub_space_bookings).dependent(:restrict_with_error) }

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

  # A room with bookings is never destroyed, and no booking or status is removed.
  it "cannot be destroyed while it has bookings" do
    create(:booking_status, :pending)
    room = create(:sub_space)
    create(:sub_space_booking, sub_space: room)
    expect(room.destroy).to be(false)
    expect(room.errors.full_messages.to_sentence).to include("bookings")
    expect(SubSpaceBooking.count).to eq(1)
    expect(described_class.exists?(room.id)).to be(true)
  end

  it "destroys when it has no bookings" do
    room = create(:sub_space)
    expect { room.destroy }.to change(SubSpace, :count).by(-1)
  end

  # The database refuses what the model refuses, so a delete that skips callbacks cannot remove a
  # room's bookings with it.
  describe "deleting without callbacks" do
    it "is refused by the database while the room has bookings, and keeps the bookings" do
      create(:booking_status, :pending)
      room = create(:sub_space)
      booking = create(:sub_space_booking, sub_space: room)
      # A savepoint, so the refused statement does not abort the example's own transaction.
      expect { described_class.transaction(requires_new: true) { room.delete } }.to raise_error(
        ActiveRecord::InvalidForeignKey
      )
      expect { described_class.transaction(requires_new: true) { described_class.where(id: room.id).delete_all } }
        .to raise_error(ActiveRecord::InvalidForeignKey)
      expect(described_class.exists?(room.id)).to be(true)
      expect(SubSpaceBooking.where(id: booking.id)).to exist
    end

    it "deletes a room that has no bookings" do
      room = create(:sub_space)
      expect { room.delete }.to change(SubSpace, :count).by(-1)
    end
  end

  describe "#booking_rules" do
    it "lists no rules for a room without limits, approval or public default" do
      expect(build(:sub_space).booking_rules).to eq([])
    end

    it "lists every rule in order, the approval rule with the automatic-approval hours" do
      room = build(:sub_space, maximum_booking_duration: 4, maximum_booking_hours_per_week: 10,
                               default_public: true, approval_required: true, max_automatic_approval_hour: 2)
      expect(room.booking_rules).to eq(
        ["has a maximum booking duration of 4 hours",
         "has a maximum booking hours per person per week of 10 hours",
         "bookings (Name and Description of event) are public by default",
         "Bookings require manual approval, bookings of 2 hours or less will be automatically approved"]
      )
    end

    it "says bookings need manual approval when there are no automatic-approval hours" do
      expect(build(:sub_space, approval_required: true).booking_rules).to eq(["bookings will require manual approval"])
    end

    it "ignores the automatic-approval hours of a room that needs no approval" do
      expect(build(:sub_space, max_automatic_approval_hour: 3).booking_rules).to eq([])
    end
  end
end
