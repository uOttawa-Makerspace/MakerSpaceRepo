# frozen_string_literal: true

require "rails_helper"

# Characterization for UserBookingApproval - request-access records.
# Identity vocabulary is closed: JMTS/Staff/GNG/Other (controller
# grant_booking_access! rewrites any other value to "Other").
# WART(D-B19) A: default_scope orders EVERY query by created_at DESC, including the
# `where(user:...).first` duplicate-request lookup.
# WART(D-B19) B: User#user_booking_approvals carries `inverse_of: :staff`, so the
# association's foreign key resolves to staff_id — the OWNER's association
# list is empty and the rows surface for the STAFF who processed them; the
# owner's list is only reachable via UserBookingApproval.where(user_id:).

RSpec.describe UserBookingApproval, type: :model do
  it "requires an identity from the closed VOCABULARY and a user" do
    uba = described_class.new
    expect(uba).not_to be_valid
    expect(uba.errors[:identity])
      .to eq(["This field is required.", "Selection is not valid."])

    uba.identity = "NotAJMTSStaffGNGOther"
    expect(uba).not_to be_valid
    expect(uba.errors[:identity]).to eq(["Selection is not valid."])

    user = create(:user, :regular_user)
    valid = described_class.new(user: user, identity: "Staff",
                                comments: "why", date: Date.today)
    expect(valid).to be_valid
  end

  it "accepts each documented identity; owner's association misses them (staff_id FK wart)" do
    user = create(:user, :regular_user)
    approver = create(:user, :staff)
    %w[JMTS Staff GNG Other].each do |ident|
      described_class.create!(user: user, staff_id: approver.id,
                              identity: ident, comments: ident,
                              date: Date.today)
    end

    # the owner's rows are reachable only through the raw model query
    expect(described_class.where(user_id: user.id).map(&:identity).sort)
      .to eq(%w[GNG JMTS Other Staff])

    # ...whereas the association (keyed on staff_id, see WART(D-B19) B above)
    # returns nothing for the owner and everything for the acting staff
    expect(user.user_booking_approvals).to be_empty
    expect(approver.user_booking_approvals.map(&:identity))
      .to eq(%w[Other GNG Staff JMTS]) # default_scope: newest first
  end

  it "default_scope orders by created_at (NEWEST first) regardless of call" do
    user = create(:user, :regular_user)
    earliest = Time.zone.local(2020, 1, 1, 12)
    a = described_class.create!(user: user, identity: "GNG",
                                comments: "a", date: Date.today,
                                created_at: earliest)
    b = described_class.create!(user: user, identity: "JMTS",
                                comments: "b", date: Date.today,
                                created_at: earliest + 1.year)

    expect(described_class.where(user: user).pluck(:id)).to eq([b.id, a.id])
  end

  it "staff_id (who approved) is optional" do
    uba = described_class.create!(
      user: create(:user, :regular_user), identity: "GNG",
      approved: false, comments: "c", date: Date.today
    )
    expect(uba.staff).to be_nil
  end
end
