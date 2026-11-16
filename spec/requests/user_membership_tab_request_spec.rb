# frozen_string_literal: true

require "rails_helper"

# The admin membership tab on a profile lists the user's paid and revoked memberships. The revoke button is
# offered on paid memberships, except faculty ones: those are granted and ended by the faculty membership check.
RSpec.describe "Profile admin membership tab", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:member) { create(:user, :regular_user) }

  before do
    post login_authentication_path, params: { username_email: admin.username, password: "asa32A353#" }
  end

  def revoke_button_for?(membership)
    get user_path(member.username)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("form[action='#{revoke_membership_path(membership)}']").present?
  end

  it "offers revoke on a paid membership of an ordinary tier" do
    membership = create(:membership, user: member, membership_tier: create(:membership_tier, title_en: "1 Day Membership"))

    expect(revoke_button_for?(membership)).to be(true)
  end

  it "does not offer revoke on a paid faculty membership" do
    tier = create(:membership_tier, title_en: "Faculty membership", title_fr: "Adhésion facultaire", hidden: true)
    membership = create(:membership, user: member, membership_tier: tier)

    expect(revoke_button_for?(membership)).to be(false)
    expect(response.body).to include("Faculty")
  end

  it "does not offer revoke on a revoked membership" do
    membership = create(:membership, user: member, status: "revoked")

    expect(revoke_button_for?(membership)).to be(false)
  end
end
