# frozen_string_literal: true

require "rails_helper"

# Characterization spec for User::UoengConcern#validate_uoeng_membership
# (chunk 9 "Identity"). In the test env `engineering?` short-circuits to
# `faculty == "Engineering"`; the real uOttawa API path is exercised by
# pretending to be non-test (Rails.env.test? stubbed) with Excon stubbed, so no
# HTTP can occur.

RSpec.describe User::UoengConcern, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let!(:tier) { MembershipTier.create!(title_en: "Faculty membership", title_fr: "Adhésion faculté", internal_price: 0, external_price: 0, duration: 120.days.to_i, hidden: true) }
  let(:eng) { create(:user, :regular_user, identity: "undergrad", faculty: "Engineering", program: "X", year_of_study: 1, student_id: "300000001") }
  let(:art) { create(:user, :regular_user, identity: "undergrad", faculty: "Arts", program: "X", year_of_study: 1, student_id: "300000002") }

  before { block_external_http! }

  def logs
    TapBoxLog.order(:id).to_a
  end

  context "in the test env (faculty shortcut)" do
    it "grants a paid faculty membership ending at the semester end for engineering users" do
      m = eng.validate_uoeng_membership
      expect(m).to be_a(Membership)
      expect(m.status).to eq("paid")
      expect(m.membership_tier).to eq(tier)
      expect(m.end_date).to be_within(1.second).of(eng.send(:end_of_this_semester))
    end

    it "is idempotent: a second call returns the same membership" do
      first = eng.validate_uoeng_membership
      expect { eng.validate_uoeng_membership }.not_to change(Membership, :count)
      expect(eng.validate_uoeng_membership).to eq(first)
    end

    it "returns nil and creates nothing for non-engineering users" do
      expect(art.validate_uoeng_membership).to be_nil
      expect(Membership.count).to eq(0)
    end

    it "revokes existing active faculty memberships when the user is no longer engineering, logging it" do
      m = create(:membership, user: art, membership_tier: tier, status: "paid", end_date: 1.month.from_now)
      expect(art.validate_uoeng_membership).to be_nil
      expect(m.reload.status).to eq("revoked")
      expect(logs.map(&:event_type)).to include(TapBoxLog::MEMBERSHIP_CHECK)
    end

    it "does not revoke other tiers" do
      other_tier = create(:membership_tier)
      m = create(:membership, user: art, membership_tier: other_tier, status: "paid", end_date: 1.month.from_now)
      art.validate_uoeng_membership
      expect(m.reload.status).to eq("paid")
    end

    it "raises when the Faculty membership tier is missing" do
      tier.destroy
      expect { eng.validate_uoeng_membership }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context "against the (stubbed) uOttawa API" do
    let(:response_class) { Struct.new(:status, :body) }

    before do
      allow(Rails.env).to receive(:test?).and_return(false)
    end

    def stub_api(status: 200, body: {})
      allow(Excon).to receive(:get).and_return(response_class.new(status, body.is_a?(String) ? body : body.to_json))
    end

    it "grants membership to a full-time GENIE student" do
      stub_api(body: { "student_this_semester" => true, "faculty" => "GENIE", "first_name" => "Ann", "last_name" => "B" })
      expect(eng.validate_uoeng_membership).to be_a(Membership)
    end

    it "grants membership to anyone enrolled in a GNG course" do
      stub_api(body: { "student_this_semester" => false, "faculty" => "ARTS", "courses_enrolled" => ["GNG1103"] })
      expect(art.validate_uoeng_membership).to be_a(Membership)
    end

    it "denies and logs a non-engineering student" do
      stub_api(body: { "student_this_semester" => true, "faculty" => "ARTS", "courses_enrolled" => [] })
      expect(art.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::MEMBERSHIP_CHECK)
    end

    it "queries by student id when present, by email for @uottawa.ca otherwise, and gives up on others" do
      stub_api(body: { "faculty" => "ARTS" })
      eng.validate_uoeng_membership
      expect(Excon).to have_received(:get).with(a_string_including("300000001"), anything)

      no_id = create(:user, :regular_user, email: "someone@uottawa.ca")
      no_id.validate_uoeng_membership
      expect(Excon).to have_received(:get).with(a_string_including("someone@uottawa.ca"), anything)

      outsider = create(:user, :regular_user, email: "someone@gmail.com")
      expect(outsider.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "logs a student-id mismatch but still evaluates the details" do
      stub_api(body: { "student_number" => "999999999", "student_this_semester" => true, "faculty" => "GENIE" })
      expect(eng.validate_uoeng_membership).to be_a(Membership)
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "logs a name mismatch" do
      stub_api(body: { "first_name" => "Zzyzx", "last_name" => "Q", "student_this_semester" => true, "faculty" => "GENIE" })
      eng.validate_uoeng_membership
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "treats a timeout as 'not engineering' (fail closed) and logs an error" do
      allow(Excon).to receive(:get).and_raise(Excon::Error::Timeout)
      expect(art.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::ERROR)
    end

    it "treats invalid JSON as 'not engineering' and logs an error" do
      stub_api(body: "<html>nope</html>")
      expect(art.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::ERROR)
    end

    it "a transient API failure revokes an existing faculty membership" do
      # WART(D-I31): API timeouts/bad JSON are treated as 'not engineering', so a flaky upstream revokes a paying engineer's faculty membership
      m = create(:membership, user: eng, membership_tier: tier, status: "paid", end_date: 1.month.from_now)
      allow(Excon).to receive(:get).and_raise(Excon::Error::Timeout)
      eng.validate_uoeng_membership
      expect(m.reload.status).to eq("revoked")
    end

    it "an HTTP error status is logged and the body still parsed" do
      stub_api(status: 500, body: { "faculty" => "GENIE", "student_this_semester" => true })
      expect(eng.validate_uoeng_membership).to be_a(Membership)
      expect(logs.map(&:event_type)).to include(TapBoxLog::ERROR)
    end
  end
end
