# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Membership check from a profile", type: :request do
  include SpacesSpecHelpers

  let!(:tier) do
    MembershipTier.create!(title_en: "Faculty membership", title_fr: "Adhésion faculté", internal_price: 0,
                           external_price: 0, duration: 120.days.to_i, hidden: true)
  end
  let(:space) { create(:space) }
  let(:target) { create(:user, :regular_user, identity: "undergrad", faculty: "Arts", program: "X", year_of_study: 1, student_id: "300000002") }
  let(:api_base) { "https://uoeng.example.test" }
  let(:genie) { { "student_this_semester" => true, "faculty" => "GENIE", "first_name" => "Ann", "last_name" => "B" } }
  let(:not_engineering) { { "student_this_semester" => true, "faculty" => "ARTS", "courses_enrolled" => [] } }

  before do
    block_external_http!
    allow(Rails.env).to receive(:test?).and_return(false)
    creds = { query_by_id: "#{api_base}/by_id/", query_by_email: "#{api_base}/by_email/", student_information_key: "k" }
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:test, :uoeng).and_return(creds)
  end

  def stub_api(status: 200, body: {})
    stub_request(:get, %r{\A#{api_base}/by_id/}).to_return(status: status, body: body.to_json)
  end

  def run_check
    post user_membership_check_path(target.username)
  end

  context "as staff" do
    before { sign_in_as(:staff, space: space) }

    it "grants a faculty membership to an eligible user" do
      stub_api(body: genie)
      expect { run_check }.to change { target.memberships.active.count }.by(1)
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:notice]).to eq(I18n.t("membership_checks.granted"))
    end

    it "ends an active faculty membership of a user who is not eligible, as a tap does" do
      m = create(:membership, user: target, membership_tier: tier, status: "paid", end_date: 1.month.from_now)
      stub_api(body: not_engineering)
      run_check
      expect(m.reload.status).to eq("revoked")
      expect(flash[:alert_yellow]).to eq(I18n.t("membership_checks.not_eligible"))
    end

    it "changes nothing and says so when the service is unavailable" do
      m = create(:membership, user: target, membership_tier: tier, status: "paid", end_date: 1.month.from_now)
      stub_api(status: 503)
      run_check
      expect(m.reload.status).to eq("paid")
      expect(flash[:alert]).to eq(I18n.t("membership_checks.unavailable"))
    end

    it "answers in French when the locale is French" do
      stub_api(body: genie)
      post user_membership_check_path(target.username, locale: :fr)
      expect(flash[:notice]).to eq(I18n.t("membership_checks.granted", locale: :fr))
    end

    it "is rate limited per checked user" do
      stub_api(body: genie)
      3.times { run_check }
      run_check
      expect(flash[:alert]).to eq(I18n.t("membership_checks.rate_limited"))
      expect(a_request(:get, %r{\A#{api_base}/by_id/})).to have_been_made.times(3)
    end

    it "is rate limited per staff member across users" do
      stub_api(body: genie)
      11.times { |i| post user_membership_check_path(create(:user, :regular_user, student_id: "4000#{i}").username) }
      expect(flash[:alert]).to eq(I18n.t("membership_checks.rate_limited"))
    end

    it "answers 404 for an unknown user" do
      post user_membership_check_path("nobody-here")
      expect(response).to have_http_status(:not_found)
    end

    it "shows the button on the profile" do
      get user_path(target.username)
      expect(response.body).to include(user_membership_check_path(target.username))
    end
  end

  context "as a regular user" do
    before { sign_in_as(:regular) }

    it "refuses the check and runs nothing" do
      run_check
      expect(response).to redirect_to(root_path)
      expect(a_request(:get, %r{\A#{api_base}})).not_to have_been_made
    end

    it "does not show the button on a profile" do
      get user_path(target.username)
      expect(response.body).not_to include(user_membership_check_path(target.username))
    end
  end

  context "as a guest" do
    it "redirects to sign in and runs nothing" do
      run_check
      expect(response).to redirect_to(login_path)
      expect(a_request(:get, %r{\A#{api_base}})).not_to have_been_made
    end
  end
end
