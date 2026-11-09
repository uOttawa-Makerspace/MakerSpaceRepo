# frozen_string_literal: true

require "rails_helper"

# Characterization for UserBookingApproval - request-access records.
# Identity vocabulary is closed: JMTS/Staff/GNG/Other (approve! rewrites
# any other value to "Other").
# default_scope orders EVERY query by created_at DESC, including the
# `where(user:...).first` duplicate-request lookup.
# User#user_booking_approvals lists the requests a user made (user_id);
# User#approved_booking_requests lists the ones a staff member approved (staff_id).

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

  it "accepts each documented identity; the owner lists them, the approving staff lists them separately" do
    user = create(:user, :regular_user)
    approver = create(:user, :staff)
    %w[JMTS Staff GNG Other].each do |ident|
      described_class.create!(user: user, staff_id: approver.id,
                              identity: ident, comments: ident,
                              date: Date.today)
    end

    expect(user.user_booking_approvals.map(&:identity))
      .to eq(%w[Other GNG Staff JMTS]) # default_scope: newest first
    expect(user.approved_booking_requests).to be_empty

    expect(approver.user_booking_approvals).to be_empty
    expect(approver.approved_booking_requests.map(&:identity))
      .to eq(%w[Other GNG Staff JMTS])
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

  describe "status" do
    let(:user) { create(:user, :regular_user) }
    let(:admin) { create(:user, :admin) }
    let(:request) { described_class.create!(user: user, identity: "GNG", comments: "c", date: Date.today) }

    it "starts pending, and the approved column mirrors the status" do
      expect(request).to have_attributes(status: "pending", approved: false)
      request.approve!(by: admin)
      expect(request.reload).to have_attributes(status: "approved", approved: true, staff_id: admin.id,
                                                decided_by_id: admin.id)
      request.revoke!(by: admin, reason: "r")
      expect(request.reload).to have_attributes(status: "revoked", approved: false, reason: "r")
    end

    it "lists the requests a user decided" do
      request.decline!(by: admin)
      expect(admin.decided_booking_requests).to contain_exactly(request)
    end

    {
      "approved" => %w[declined pending],
      "declined" => %w[approved revoked pending],
      "revoked" => %w[approved declined pending]
    }.each do |from, targets|
      targets.each do |to|
        it "does not go from #{from} to #{to}" do
          request.update_columns(status: from)
          request.status = to
          expect(request).not_to be_valid
          expect(request.errors[:base]).to eq(["This request was already #{from}."])
        end
      end
    end

    it "does not revoke a pending request" do
      expect { request.revoke!(by: admin) }.to raise_error(ActiveRecord::RecordInvalid, /already pending/)
    end

    it "refuses an unknown status" do
      request.status = "lost"
      expect(request).not_to be_valid
    end

    it "checks the identity only when it is set or the request is new" do
      request.update_columns(identity: nil)
      expect(request.reload).to be_valid
      request.identity = "Nope"
      expect(request).not_to be_valid
    end

    it "keeps a decision when the deciding account is deleted" do
      request.decline!(by: admin)
      admin.delete
      expect(request.reload).to have_attributes(status: "declined", decided_by_id: nil)
    end
  end
end
