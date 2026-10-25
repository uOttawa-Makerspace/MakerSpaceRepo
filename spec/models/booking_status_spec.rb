# frozen_string_literal: true

require "rails_helper"
require "open3"

# Characterization for BookingStatus: plain lookup table w/ a unique name.
# NOTE BookingStatus::PENDING/APPROVED/DECLINED are constants resolved at
# boot (nil on an empty test DB) — the suite stubs them per example, which
# is itself documentation of the wart (no rake task seeds them in test).

RSpec.describe BookingStatus, type: :model do
  before do
    @pending = described_class.create!(name: "Pending")
    @approved = create(:booking_status, :approved)
    @declined = create(:booking_status, :rejected)
    stub_const("BookingStatus::PENDING", @pending)
    stub_const("BookingStatus::APPROVED", @approved)
    stub_const("BookingStatus::DECLINED", @declined)
  end

  # WART(D-B22): the constants are `BookingStatus.find_by(...)` evaluated in the
  # class body. A process booted against a database without the reference rows
  # (fresh deploy, assets:precompile) keeps nil for its whole lifetime. The
  # other examples stub the constants, so this boots a REAL process: the rows
  # created by `before` above are uncommitted (transactional example), exactly
  # like an empty database from the subprocess's point of view.
  it "resolves PENDING/APPROVED/DECLINED once at boot: nil in a process booted without the rows" do
    out, status = Open3.capture2e(
      { "RAILS_ENV" => "test" },
      "bin/rails", "runner",
      'puts "CONSTANTS=" + [BookingStatus::PENDING, BookingStatus::APPROVED, ' \
      'BookingStatus::DECLINED].map(&:inspect).join(",")',
      chdir: Rails.root.to_s
    )
    expect(status).to be_success
    expect(out.lines.grep(/\ACONSTANTS=/).last.strip).to eq("CONSTANTS=nil,nil,nil")
  end

  it "requires + unique name" do
    dup = described_class.new(name: "Pending")
    expect(dup).not_to be_valid
    expect(dup.errors[:name]).to include("has already been taken")

    blank = described_class.new
    expect(blank).not_to be_valid
  end

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
