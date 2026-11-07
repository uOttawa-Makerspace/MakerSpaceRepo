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

  # dependent: :destroy deletes every linked status row
  it "destroying a status nukes its linking rows (dependent: :destroy)" do
    booking = create(:sub_space_booking)
    link = SubSpaceBookingStatus.create!(
      sub_space_booking: booking, booking_status: @pending
    )
    booking.update_column(:sub_space_booking_status_id, link.id)
    # both the factory's status row and the manually added one point at Pending
    expect(
      SubSpaceBookingStatus.where(booking_status_id: @pending.id).count
    ).to eq(2)
    @pending.destroy
    expect(SubSpaceBookingStatus.where(booking_status_id: @pending.id).count)
      .to eq(0)
    expect(SubSpaceBookingStatus.find_by(id: link.id)).to be_nil
  end
end
