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
    let(:genie) { { "student_this_semester" => true, "faculty" => "GENIE", "first_name" => "Ann", "last_name" => "B" } }
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

    it "revokes when the upstream sends the usual not-engineering answer with null fields, without an error row" do
      m = paid_faculty_membership(art)
      stub_api(body: { "student_this_semester" => nil, "faculty" => nil, "courses_enrolled" => nil })
      expect(art.validate_uoeng_membership).to be_nil
      expect(m.reload.status).to eq("revoked")
      expect(logs.map(&:event_type)).not_to include(TapBoxLog::ERROR)
    end

    it "revokes when courses_enrolled is missing from the answer" do
      m = paid_faculty_membership(art)
      stub_api(body: { "student_this_semester" => true, "faculty" => "ARTS" })
      expect(art.validate_uoeng_membership).to be_nil
      expect(m.reload.status).to eq("revoked")
    end

    it "queries by student id when present, by email for @uottawa.ca otherwise, and gives up on others" do
      id_request = stub_api(body: { "faculty" => "ARTS" })
      eng.validate_uoeng_membership
      expect(id_request).to have_been_requested.with { |req| req.uri.to_s.include?("300000001") }

      no_id = create(:user, :regular_user, email: "someone@uottawa.ca")
      email_request = stub_api(email_url, body: { "faculty" => "ARTS" })
      no_id.validate_uoeng_membership
      expect(email_request).to have_been_requested

      outsider = create(:user, :regular_user, email: "someone@gmail.com")
      expect(outsider.validate_uoeng_membership).to eq(:unknown)
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    describe "for a user that cannot be looked up (no student id, no @uottawa.ca email)" do
      let(:outsider) { create(:user, :regular_user, email: "someone@gmail.com", student_id: nil) }

      it "keeps an existing faculty membership, with a warning and no revocation" do
        m = paid_faculty_membership(outsider)
        expect(outsider.validate_uoeng_membership).to eq(:unknown)
        expect(m.reload.status).to eq("paid")
        expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
        expect(logs.map(&:event_type)).not_to include(TapBoxLog::MEMBERSHIP_CHECK)
        expect(a_request(:get, /uoeng/)).not_to have_been_made
      end

      it "grants no membership to a user without one" do
        expect(outsider.validate_uoeng_membership).to eq(:unknown)
        expect(outsider.memberships).to be_empty
      end
    end

    describe "when the student number in the answer differs from the one on the account" do
      # The answer shape uOEng sends: the number is `emplid`, an integer.
      let(:other_student) do
        { "emplid" => 999_999_999, "first_name" => "Ann", "last_name" => "B", "email_addr" => "ann@example.test",
          "student_this_semester" => true, "fulltime" => true, "faculty" => "GENIE", "program_level" => "undergraduate",
          "program_options" => [""], "courses_enrolled" => [] }
      end

      before { stub_api(body: other_student) }

      it "grants no faculty membership and answers :mismatch" do
        expect(eng.validate_uoeng_membership).to eq(:mismatch)
        expect(eng.memberships).to be_empty
      end

      it "keeps an existing faculty membership as it is" do
        m = paid_faculty_membership(eng)
        expect(eng.validate_uoeng_membership).to eq(:mismatch)
        expect(m.reload.status).to eq("paid")
      end

      it "keeps the typed student number" do
        eng.validate_uoeng_membership
        expect(eng.reload.student_id).to eq("300000001")
      end

      it "writes a warning row for staff saying the grant was withheld" do
        eng.validate_uoeng_membership
        row = logs.find { |l| l.details&.dig("reason") == "student_id_mismatch" }
        expect(row.event_type).to eq(TapBoxLog::WARNING)
        expect(row.user).to eq(eng)
        expect(row.details).to include("faculty_membership" => "not granted")
        expect(row.details["suggestion"]).to include("No faculty membership was granted")
      end

      it "also blocks when the answer sends the number as student_number" do
        stub_api(body: genie.merge("student_number" => "999999999"))
        expect(eng.validate_uoeng_membership).to eq(:mismatch)
        expect(eng.memberships).to be_empty
      end
    end

    describe "when the student number in the answer matches the one on the account" do
      it "grants the membership and writes no mismatch row, for an integer emplid" do
        stub_api(body: genie.merge("emplid" => 300_000_001))
        expect(eng.validate_uoeng_membership).to be_a(Membership)
        expect(logs.map { |l| l.details&.dig("reason") }).not_to include("student_id_mismatch")
      end

      {
        ["012345678", 12_345_678] => true,
        ["012345678", "012345678"] => true,
        ["123456789", 123_456_780] => false,
        ["A12345", "a12345"] => false,
        ["A12345", "A12345"] => true
      }.each do |(typed, sent), granted|
        it "#{granted ? 'grants' : 'withholds'} the membership for typed #{typed.inspect} and answer #{sent.inspect}" do
          eng.update_column(:student_id, typed)
          stub_api(body: genie.merge("emplid" => sent))
          expect(eng.validate_uoeng_membership).to(granted ? be_a(Membership) : eq(:mismatch))
        end
      end

      it "grants the membership for a student_number string" do
        stub_api(body: genie.merge("student_number" => "300000001"))
        expect(eng.validate_uoeng_membership).to be_a(Membership)
      end

      it "grants the membership when the answer carries no student number" do
        stub_api(body: genie)
        expect(eng.validate_uoeng_membership).to be_a(Membership)
      end
    end

    it "logs a name mismatch" do
      stub_api(body: { "first_name" => "Zzyzx", "last_name" => "Q", "student_this_semester" => true, "faculty" => "GENIE" })
      eng.validate_uoeng_membership
      expect(logs.map(&:event_type)).to include(TapBoxLog::WARNING)
    end

    it "stores only the differing field in the student-id mismatch row" do
      stub_api(body: { "emplid" => 999_999_999, "student_this_semester" => true, "faculty" => "GENIE" })
      eng.validate_uoeng_membership
      row = logs.find { |l| l.details&.dig("reason") == "student_id_mismatch" }
      expect(row.details).to include("differing_field" => "student number")
      expect(row.message + row.details.to_json).not_to include("999999999", eng.student_id)
    end

    it "stores only the differing field in the name mismatch row" do
      stub_api(body: { "first_name" => "Zzyzx", "last_name" => "Q", "student_this_semester" => true, "faculty" => "GENIE" })
      eng.validate_uoeng_membership
      row = logs.find { |l| l.details&.dig("reason") == "name_mismatch" }
      expect(row.details).to include("differing_field" => "name")
      expect(row.message + row.details.to_json).not_to include("Zzyzx", eng.name)
    end

    describe "when the upstream cannot give an answer" do
      let!(:membership) { paid_faculty_membership(eng) }
      transient = ["a timeout", "a refused connection", "a 500 answer"]

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
        "a wrong-typed student_this_semester" => -> { stub_api(body: genie.merge("student_this_semester" => "yes")) },
        "a wrong-typed faculty" => -> { stub_api(body: genie.merge("faculty" => 7)) },
        "a wrong-typed first_name" => -> { stub_api(body: genie.merge("first_name" => ["Ann"])) },
        "a wrong-typed last_name" => -> { stub_api(body: genie.merge("last_name" => 5)) }
      }.each do |failure, arrange|
        it "keeps the stored membership and reports the result as #{transient.include?(failure) ? "unavailable" : "unknown"} on #{failure}" do
          instance_exec(&arrange)

          expect(eng.validate_uoeng_membership).to eq(transient.include?(failure) ? :unavailable : :unknown)

          expect(membership.reload.status).to eq("paid")
          expect(Membership.where(user: eng).count).to eq(1)
          expect(logs.map(&:event_type)).to include(TapBoxLog::ERROR)
        end
      end

      describe "the error log row" do
        let(:full_answer) do
          {
            "emplid" => "300000001", "first_name" => "Ann", "last_name" => "Tester", "email_addr" => "ann@example.test",
            "correspondence_lang" => "ENG", "legal_status" => "Canadian", "sex" => "F", "student_this_semester" => true,
            "fulltime" => true, "faculty" => "GENIE", "program_level" => "Undergraduate", "program" => "Software",
            "program_description" => "BASc", "program_options" => [], "academic_unit" => "Engineering",
            "courses_enrolled" => ["GNG1103"]
          }
        end

        def error_details
          logs.find { |row| row.event_type == TapBoxLog::ERROR }.details
        end

        it "after an HTTP error holds the status and shape, never the personal fields" do
          stub_api(status: 503, body: full_answer)
          eng.validate_uoeng_membership

          details = error_details
          expect(details).to include("reason" => "uoeng_http_error", "http_status" => 503)
          expect(details["response"]).to include("keys" => full_answer.keys, "values" => full_answer.slice("student_this_semester", "faculty"))
          expect(details["response"]["body_size"]).to eq(full_answer.to_json.bytesize)
          expect(details.to_json).not_to match(/Canadian|Tester|ann@example|"F"|BASc/)
          expect(details["response"]["values"]).not_to have_key("courses_enrolled")
          expect(details.to_json).not_to include("GNG1103")
        end

        it "after an answer of the wrong shape holds the same summary" do
          stub_api(body: full_answer.merge("faculty" => { "name" => "Ann Tester" }))
          eng.validate_uoeng_membership

          details = error_details
          expect(details["reason"]).to eq("uoeng_bad_json")
          expect(details["response"]["values"]["faculty"]).to eq("Hash")
          expect(details.to_json).not_to match(/Canadian|Tester|ann@example|BASc/)
        end

        it "after a body that is not JSON holds only its size and content type" do
          page = "<html>Ann Tester, F, Canadian</html>"
          stub_request(:get, id_url).to_return(status: 502, body: page, headers: { "Content-Type" => "text/html" })
          eng.validate_uoeng_membership

          expect(error_details["response"]).to eq("body_size" => page.bytesize, "content_type" => "text/html")
          expect(error_details.to_json).not_to match(/Tester|Canadian/)
        end

        it "after a malformed body holds no text of the body, in the row or in the reported error" do
          stub_api(body: '{"first_name":"Jane","email_addr":"jane.doe@example.test" oops')
          reported = []
          allow(Rails.error).to receive(:report) { |error, **| reported << error }
          eng.validate_uoeng_membership

          details = error_details
          expect(details).to include("reason" => "uoeng_bad_json", "exception_class" => "JSON::ParserError", "error" => "could not be read as JSON")
          expect(details.to_json).not_to match(/Jane|jane\.doe|email_addr/)
          expect(reported.map(&:message).join).not_to match(/Jane|jane\.doe|email_addr/)
          expect(reported.size).to eq(1)
        end

        it "after an answer of the wrong shape names the reason without body text" do
          stub_api(body: full_answer.merge("faculty" => 7))
          eng.validate_uoeng_membership

          expect(error_details).to include("exception_class" => "User::UoengConcern::UnexpectedShape", "error" => "unexpected answer shape")
        end

        it "is still shown by the staff console row" do
          stub_api(status: 503, body: full_answer)
          eng.validate_uoeng_membership
          html = ApplicationController.render(partial: "staff/tap_box_console/log_row", locals: { log: logs.find { |r| r.event_type == TapBoxLog::ERROR } })

          expect(html).to include("uoeng_http_error", "http_status=", "student_this_semester")
          expect(html).not_to include("Canadian")
        end
      end

      it "does not create a membership for a user without one" do
        stub_request(:get, id_url).to_timeout
        expect(art.validate_uoeng_membership).to eq(:unavailable)
        expect(art.memberships).to be_empty
      end

      it "does not log a revocation" do
        stub_request(:get, id_url).to_timeout
        eng.validate_uoeng_membership
        expect(logs.map(&:message).grep(/revok/i)).to be_empty
      end

      it "answers normally again once the upstream recovers" do
        stub_request(:get, id_url).to_timeout.then.to_return(status: 200, body: not_engineering.to_json)
        expect(eng.validate_uoeng_membership).to eq(:unavailable)
        expect(eng.validate_uoeng_membership).to be_nil
        expect(membership.reload.status).to eq("revoked")
      end
    end
  end
end
