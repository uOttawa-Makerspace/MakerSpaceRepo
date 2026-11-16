# frozen_string_literal: true

require "rails_helper"

# Who can set a user's identity, and so whether the internal or the external
# price applies to them. A uOttawa student, faculty or staff identity can be
# chosen at sign-up or on the profile form only with a confirmed @uottawa.ca
# email. The admin user form and the API do not write the identity.
RSpec.describe "User identity and membership price", type: :request do
  let(:password) { "asa32A353#" }
  let(:tier) { create(:membership_tier, internal_price: 10, external_price: 50) }
  let(:student_fields) { { program: "X", faculty: "Engineering", year_of_study: 1 } }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def outside_member(**attrs)
    create(:user, :regular_user, identity: "community_member", email: "member@example.com", **attrs)
  end

  describe "profile update" do
    it "refuses a faculty identity for a member with an outside email" do
      member = outside_member
      login!(member)

      patch user_path(member.username), params: { user: { identity: "faculty_member" } }

      expect(flash[:alert]).to include("confirmed @uottawa.ca email address")
      expect(member.reload.identity).to eq("community_member")
      expect(tier.price(member)).to eq(50)
    end

    it "refuses a student identity for a member with an outside email, whatever the student number" do
      member = outside_member
      login!(member)

      patch user_path(member.username),
            params: { user: { identity: "undergrad", student_id: "1234567", **student_fields } }

      expect(flash[:alert]).to include("confirmed @uottawa.ca email address")
      expect(member.reload.identity).to eq("community_member")
    end

    it "accepts a faculty identity for a confirmed uOttawa email, and the internal price applies" do
      member = create(:user, :regular_user, identity: "community_member", email: "prof@uottawa.ca")
      login!(member)

      patch user_path(member.username), params: { user: { identity: "faculty_member" } }

      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(member.reload.identity).to eq("faculty_member")
      expect(tier.price(member)).to eq(10)
    end

    it "refuses a student identity even when uOEng has a record with the same student number" do
      member = outside_member(student_id: "1234567")
      UoengProfile.record!(member, { "emplid" => "1234567" }, source: "student_number")
      login!(member)

      patch user_path(member.username),
            params: { user: { identity: "undergrad", student_id: "1234567", **student_fields } }

      expect(flash[:alert]).to include("confirmed @uottawa.ca email address")
      expect(member.reload.identity).to eq("community_member")
    end

    it "refuses a switch from one internal identity to another for an account without proof" do
      member = outside_member(student_id: "1234567")
      member.update_columns(identity: "undergrad", program: "X", faculty: "Engineering")
      login!(member)

      patch user_path(member.username), params: { user: { identity: "grad", **student_fields } }

      expect(flash[:alert]).to include("confirmed @uottawa.ca email address")
      expect(member.reload.identity).to eq("undergrad")
    end

    it "keeps an existing internal identity without proof while other fields change" do
      member = outside_member
      member.update_columns(identity: "staff_member")
      login!(member)

      patch user_path(member.username), params: { user: { name: "Renamed", identity: "staff_member" } }

      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(member.reload).to have_attributes(name: "Renamed", identity: "staff_member")
    end

    it "refuses an identity outside the known list" do
      member = outside_member
      login!(member)

      patch user_path(member.username), params: { user: { identity: "admin" } }

      expect(flash[:alert]).to be_present
      expect(member.reload.identity).to eq("community_member")
    end
  end

  describe "sign-up" do
    def sign_up(**overrides)
      attrs = FactoryBot.attributes_for(:user, :regular_user, password: password).merge(overrides)
      post users_path, params: { user: attrs }
      User.find_by(username: attrs[:username])
    end

    it "refuses a staff identity with an outside email" do
      expect { sign_up(identity: "staff_member", email: "newcomer@example.com") }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("confirmed @uottawa.ca email address")
    end

    it "accepts a staff identity with a uOttawa email, which the account confirms before it can sign in" do
      created = sign_up(identity: "staff_member", email: "newcomer@uottawa.ca")

      expect(created).to have_attributes(identity: "staff_member", confirmed: false)
      expect(tier.price(created)).to eq(10)
    end

    it "accepts a community identity with an outside email" do
      created = sign_up(identity: "community_member", email: "newcomer@example.com")

      expect(tier.price(created)).to eq(50)
    end
  end

  describe "admin user form" do
    it "does not change the identity" do
      admin = create(:user, :admin)
      member = outside_member
      login!(admin)

      patch admin_user_path(member), params: { user: { identity: "faculty_member", gender: "Female" } }

      member.reload
      expect(member.gender).to eq("Female")
      expect(member.identity).to eq("community_member")
    end
  end

  describe "/api/v1" do
    it "does not change the identity through the role endpoint" do
      admin = create(:user, :admin)
      member = outside_member
      token = ApiAccessToken.issue(admin).first

      patch "/api/v1/users/#{member.id}/role",
            params: { role: "staff", identity: "faculty_member", user: { identity: "faculty_member" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json",
                       "Authorization" => "Bearer #{token}" }

      expect(response).to have_http_status(:no_content)
      expect(member.reload).to have_attributes(role: "staff", identity: "community_member")
    end
  end
end
