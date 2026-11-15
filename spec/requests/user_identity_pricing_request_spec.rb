# frozen_string_literal: true

require "rails_helper"

# Who can set a user's identity, and so whether the internal or the external
# membership price applies to them. This pins today's behaviour: the member
# picks any account identity at sign-up and on the profile form, and the server
# only checks the value is a known identity (a student identity also needs a
# student number of 7 to 12 digits). Nothing checks the email domain or asks
# uOEng. The admin user form and the API do not write the identity.
RSpec.describe "User identity and membership price", type: :request do
  let(:password) { "asa32A353#" }
  let(:tier) { create(:membership_tier, internal_price: 10, external_price: 50) }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  def outside_member
    create(:user, :regular_user, identity: "community_member", email: "member@example.com")
  end

  describe "profile update" do
    it "saves a staff identity chosen by a member with an outside email, and the internal price applies" do
      member = outside_member
      expect(tier.price(member)).to eq(50)
      login!(member)

      patch user_path(member.username), params: { user: { identity: "faculty_member" } }

      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(member.reload.identity).to eq("faculty_member")
      expect(tier.price(member)).to eq(10)
    end

    it "saves a student identity with any well-formed student number" do
      member = outside_member
      login!(member)

      patch user_path(member.username),
            params: { user: { identity: "undergrad", student_id: "1234567", program: "X",
                              faculty: "Engineering", year_of_study: 1 } }

      expect(member.reload.identity).to eq("undergrad")
      expect(tier.price(member)).to eq(10)
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
    it "creates an account with a staff identity and an outside email" do
      attrs = FactoryBot.attributes_for(:user, :regular_user, password: password)
                        .merge(identity: "staff_member", email: "newcomer@example.com")

      expect { post users_path, params: { user: attrs } }.to change(User, :count).by(1)

      created = User.find_by(username: attrs[:username])
      expect(created.identity).to eq("staff_member")
      expect(tier.price(created)).to eq(10)
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
end
