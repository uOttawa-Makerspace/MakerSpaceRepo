# frozen_string_literal: true

require "rails_helper"
require "open3"

# Characterization for BookingStatus: plain lookup table w/ a unique name.
# NOTE BookingStatus.pending/approved/declined look the rows up by name on
# every call, so they work in a process that booted against an empty database.

RSpec.describe BookingStatus, type: :model do
  before do
    @pending = described_class.create!(name: "Pending")
    @approved = create(:booking_status, :approved)
    @declined = create(:booking_status, :rejected)
  end

  it "looks the Pending, Approved and Declined rows up by name" do
    expect(described_class.pending).to eq(@pending)
    expect(described_class.approved).to eq(@approved)
    expect(described_class.declined).to eq(@declined)
  end

  # a process booted against a database without the reference rows (fresh
  # deploy, assets:precompile) must still load the class, and look the rows up
  # once they exist. The rows created by `before` above are uncommitted
  # (transactional example), exactly like an empty database from the
  # subprocess's point of view.
  it "loads in a process booted without the rows, and raises only when a row is asked for" do
    out, status = Open3.capture2e(
      { "RAILS_ENV" => "test" },
      "bin/rails", "runner",
      'puts "RESULT=" + begin; BookingStatus.approved; "found"; ' \
      'rescue ActiveRecord::RecordNotFound; "missing"; end',
      chdir: Rails.root.to_s
    )
    expect(status).to be_success
    expect(out.lines.grep(/\ARESULT=/).last.strip).to eq("RESULT=missing")
  end

  it "requires + unique name" do
    dup = described_class.new(name: "Pending")
    expect(dup).not_to be_valid
    expect(dup.errors[:name]).to include("has already been taken")

    blank = described_class.new
    expect(blank).not_to be_valid
  end

  describe "destroy" do
    it "refuses while bookings use the status, and deletes nothing" do
      booking = create(:sub_space_booking)
      link_id = booking.sub_space_booking_status_id

      expect(@pending.destroy).to be(false)

      expect(@pending.errors[:base]).not_to be_empty
      expect(described_class.exists?(@pending.id)).to be(true)
      expect(SubSpaceBooking.exists?(booking.id)).to be(true)
      expect(SubSpaceBookingStatus.exists?(link_id)).to be(true)
    end

    it "refuses while only a booking's status column uses it" do
      booking = create(:sub_space_booking)
      booking.update_columns(sub_space_booking_status_id: nil)
      SubSpaceBookingStatus.where(sub_space_booking_id: booking.id).delete_all

      expect(@pending.destroy).to be(false)
      expect(described_class.exists?(@pending.id)).to be(true)
    end

    it "destroys a status nothing uses" do
      unused = described_class.create!(name: "Archived")

      expect(unused.destroy).to be_truthy
      expect(described_class.exists?(unused.id)).to be(false)
    end
  end
end
