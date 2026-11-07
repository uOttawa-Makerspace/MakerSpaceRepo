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
    let(:api_base) { "https://uoeng.example.test" }
    let(:id_url) { %r{\A#{api_base}/by_id/} }
    let(:email_url) { %r{\A#{api_base}/by_email/} }
    let(:genie) { { "student_this_semester" => true, "faculty" => "GENIE", "courses_enrolled" => [], "first_name" => "Ann", "last_name" => "B" } }
    let(:not_engineering) { { "student_this_semester" => true, "faculty" => "ARTS", "courses_enrolled" => [] } }

    before do
      allow(Rails.env).to receive(:test?).and_return(false)
      creds = { query_by_id: "#{api_base}/by_id/", query_by_email: "#{api_base}/by_email/", student_information_key: "k" }
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:test, :uoeng).and_return(creds)
    end

    def stub_api(url = id_url, status: 200, body: {})
      stub_request(:get, url).to_return(status: status, body: body.is_a?(String) ? body : body.to_json)
    end

    def paid_faculty_membership(user)
      create(:membership, user: user, membership_tier: tier, status: "paid", end_date: 1.month.from_now)
    end

    it "grants membership to a full-time GENIE student" do
      stub_api(body: genie)
      expect(eng.validate_uoeng_membership).to be_a(Membership)
    end

    it "grants membership to anyone enrolled in a GNG course" do
      stub_api(body: { "student_this_semester" => false, "faculty" => "ARTS", "courses_enrolled" => ["GNG1103"] })
      expect(art.validate_uoeng_membership).to be_a(Membership)
    end

    it "denies and logs a non-engineering student" do
      stub_api(body: not_engineering)
      expect(art.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::MEMBERSHIP_CHECK)
    end

    it "revokes the faculty membership when the upstream answers that the user is not engineering" do
      m = paid_faculty_membership(art)
      stub_api(body: not_engineering)
      expect(art.validate_uoeng_membership).to be_nil
      expect(m.reload.status).to eq("revoked")
    end

    it "queries by student id when present, by email for @uottawa.ca otherwise, and gives up on others" do
      id_request = stub_api(body: { "faculty" => "ARTS", "courses_enrolled" => [] })
      eng.validate_uoeng_membership
      expect(id_request).to have_been_requested.with { |req| req.uri.to_s.include?("300000001") }

      no_id = create(:user, :regular_user, email: "someone@uottawa.ca")
      email_request = stub_api(email_url, body: { "faculty" => "ARTS", "courses_enrolled" => [] })
      no_id.validate_uoeng_membership
      expect(email_request).to have_been_requested

      outsider = create(:user, :regular_user, email: "someone@gmail.com")
      expect(outsider.validate_uoeng_membership).to be_nil
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "logs a student-id mismatch but still evaluates the details" do
      stub_api(body: { "student_number" => "999999999", "student_this_semester" => true, "faculty" => "GENIE", "courses_enrolled" => [] })
      expect(eng.validate_uoeng_membership).to be_a(Membership)
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "logs a name mismatch" do
      stub_api(body: { "first_name" => "Zzyzx", "last_name" => "Q", "student_this_semester" => true, "faculty" => "GENIE", "courses_enrolled" => [] })
      eng.validate_uoeng_membership
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    describe "when the upstream cannot give an answer" do
      let!(:membership) { paid_faculty_membership(eng) }

      {
        "a timeout" => -> { stub_request(:get, id_url).to_timeout },
        "a refused connection" => -> { stub_request(:get, id_url).to_raise(Excon::Error::Socket.new(Errno::ECONNREFUSED.new)) },
        "a 500 answer" => -> { stub_api(status: 500, body: genie) },
        "a 404 answer" => -> { stub_api(status: 404, body: "not found") },
        "malformed JSON" => -> { stub_api(body: "<html>nope</html>") },
        "a JSON answer that is not an object" => -> { stub_api(body: "null") },
        "a JSON array answer" => -> { stub_api(body: [nil]) },
        "courses_enrolled as a string" => -> { stub_api(body: genie.merge("courses_enrolled" => "GNG1103")) },
        "courses_enrolled as [null]" => -> { stub_api(body: genie.merge("courses_enrolled" => [nil])) },
        "courses_enrolled with non-string entries" => -> { stub_api(body: genie.merge("courses_enrolled" => [1103, { "a" => 1 }])) },
        "a missing courses_enrolled" => -> { stub_api(body: genie.except("courses_enrolled")) },
        "a wrong-typed first_name" => -> { stub_api(body: genie.merge("first_name" => ["Ann"])) },
        "a wrong-typed last_name" => -> { stub_api(body: genie.merge("last_name" => 5)) }
      }.each do |failure, arrange|
        it "keeps the stored membership and reports the result as unknown on #{failure}" do
          instance_exec(&arrange)

          expect(eng.validate_uoeng_membership).to eq(:unknown)

          expect(membership.reload.status).to eq("paid")
          expect(Membership.where(user: eng).count).to eq(1)
          expect(logs.map(&:event_type)).to include(TapBoxLog::ERROR)
        end
      end

      it "does not create a membership for a user without one" do
        stub_request(:get, id_url).to_timeout
        expect(art.validate_uoeng_membership).to eq(:unknown)
        expect(art.memberships).to be_empty
      end

      it "does not log a revocation" do
        stub_request(:get, id_url).to_timeout
        eng.validate_uoeng_membership
        expect(logs.map(&:message).grep(/revok/i)).to be_empty
      end

      it "answers normally again once the upstream recovers" do
        stub_request(:get, id_url).to_timeout.then.to_return(status: 200, body: not_engineering.to_json)
        expect(eng.validate_uoeng_membership).to eq(:unknown)
        expect(eng.validate_uoeng_membership).to be_nil
        expect(membership.reload.status).to eq("revoked")
      end
    end
  end
end
