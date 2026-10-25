# frozen_string_literal: true

require "rails_helper"

# Characterization spec for the signed-in side of UsersController: profile
# show/update, avatar, password change, flags, programs, search, likes, and the
# soft-delete / inactive visibility rules (`default_scope { where(deleted: false) }`).
# Chunk 9 "Identity". Defects are PINNED, not fixed.

RSpec.describe "Users profile (HTTP contract)", type: :request do
  let(:password) { "asa32A353#" }
  let(:user) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }

  before do
    block_external_http!
    # GET /:username builds an Octokit client for the repo owner; stub the seam
    # so no HTTP is attempted (unauthenticated => no GitHub login).
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
  end

  def login!(u, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
    u
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  def json
    JSON.parse(response.body)
  end

  describe "settings pages" do
    it "guest is redirected to login with back_to" do
      get settings_profile_path
      expect(response).to redirect_to(login_path(back_to: "/settings/profile"))
      get settings_admin_path
      expect(response).to redirect_to(login_path(back_to: "/settings/admin"))
    end

    it "signed-in user sees profile and account settings" do
      login!(user)
      get settings_profile_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("user[name]")
      get settings_admin_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /:username (show)" do
    it "guest: 200 public profile page" do
      get user_path(user.username)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.username)
    end

    it "username lookup is case-insensitive" do
      get user_path(user.username.upcase)
      expect(response).to have_http_status(:ok)
    end

    it "unknown username: 404" do
      get user_path("nosuchuser")
      expect(response).to have_http_status(:not_found)
    end

    it "json: guest gets 401 with an empty body" do
      get user_path(user.username), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to be_blank
    end

    it "json: a regular user gets 401 for someone else" do
      login!(other)
      get user_path(user.username), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "json: own profile returns user, programs, certifications" do
      login!(user)
      get user_path(user.username), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.keys).to match_array(%w[user programs certifications])
      expect(json["user"]["username"]).to eq(user.username)
    end

    it "json: staff and admin may read anyone" do
      login!(staff)
      get user_path(user.username), as: :json
      expect(response).to have_http_status(:ok)
      login!(admin)
      get user_path(user.username), as: :json
      expect(response).to have_http_status(:ok)
    end

    it "json exposes the bcrypt hash and flag fields of the profile owner/staff view" do
      # WART(D-I02): serialised users include the `password` hash column (also in login/check_signed_in)
      login!(staff)
      get user_path(user.username), as: :json
      expect(json["user"]["password"]).to start_with("$2")
    end

    it "inactive (active: false) users still have a visible profile" do
      u = create(:user, :regular_user, active: false)
      get user_path(u.username)
      expect(response).to have_http_status(:ok)
    end

    context "soft-deleted user (deleted: true)" do
      let!(:gone) { create(:user, :regular_user, deleted: true) }

      it "is invisible to guests and regular users (404)" do
        get user_path(gone.username)
        expect(response).to have_http_status(:not_found)
        login!(other)
        get user_path(gone.username)
        expect(response).to have_http_status(:not_found)
      end

      it "is visible to staff and admin through User.unscoped" do
        login!(staff)
        get user_path(gone.username)
        expect(response).to have_http_status(:ok)
        login!(admin)
        get user_path(gone.username)
        expect(response).to have_http_status(:ok)
      end
    end

    it "private repos are hidden from non-owners and shown to the owner and admin" do
      repo = create(:repository, :private)
      repo.users << user
      repos = -> { controller.instance_variable_get(:@repositories).to_a }
      get user_path(user.username)
      expect(repos.call).to eq([])
      login!(other)
      get user_path(user.username)
      expect(repos.call).to eq([])
      login!(user)
      get user_path(user.username)
      expect(repos.call).to eq([repo])
      login!(admin)
      get user_path(user.username)
      expect(repos.call).to eq([repo])
    end

    it "staff (non-admin) does not see another user's private repos" do
      create(:repository, :private).users << user
      login!(staff)
      get user_path(user.username)
      expect(controller.instance_variable_get(:@repositories).to_a).to eq([])
    end
  end

  describe "PATCH /:username (update)" do
    it "guest is redirected to login" do
      patch user_path(user.username), params: { user: { name: "X" } }
      expect(response).to have_http_status(:found)
      expect(response.location).to start_with("http://www.example.com/login")
      expect(user.reload.name).not_to eq("X")
    end

    it "updates the signed-in user and redirects with notice" do
      login!(user)
      patch user_path(user.username), params: { user: { name: "Jane Doe" } }
      expect(response).to redirect_to(settings_profile_path)
      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(user.reload.name).to eq("Jane Doe")
    end

    it "ignores the :username in the path: always updates the session user" do
      login!(user)
      patch user_path(other.username), params: { user: { name: "Hijack" } }
      expect(user.reload.name).to eq("Hijack")
      expect(other.reload.name).not_to eq("Hijack")
    end

    it "validation failure: redirect with alert listing errors, nothing saved" do
      login!(user)
      patch user_path(user.username), params: { user: { name: "" } }
      expect(response).to redirect_to(settings_profile_path)
      expect(flash[:alert]).to start_with("Could not save changes. ")
      expect(flash[:alert]).to include("Name")
    end

    it "does not allow mass-assigning role, confirmed or locked" do
      login!(user)
      patch user_path(user.username), params: { user: { name: "Z Z", role: "admin", confirmed: false, locked: true } }
      user.reload
      expect(user.role).to eq("regular_user")
      expect(user.confirmed).to be(true)
      expect(user.locked).to be(false)
    end

    it "can change username and lets it collide only on case-insensitive uniqueness" do
      login!(user)
      patch user_path(user.username), params: { user: { username: other.username.upcase } }
      expect(flash[:alert]).to include("Username")
    end

    it "changes the email immediately without confirmation or notice" do
      # WART(D-I15): profile update permits :email directly, bypassing the confirm-by-email flow (and the email-changed notice to the old address)
      login!(user)
      patch user_path(user.username), params: { user: { email: "swapped@example.com" } }
      expect(response).to redirect_to(settings_profile_path)
      expect(user.reload.email).to eq("swapped@example.com")
      expect(deliveries).to be_empty
    end

    it "sets a raw plaintext password into the hash column, which then breaks login" do
      # WART(D-I16): profile update permits :password; it is stored unhashed (the strength validator sees the raw value) and later logins raise BCrypt InvalidHash (500)
      login!(user)
      patch user_path(user.username),
            params: { user: { password: "NewPassw0rd!x#9", password_confirmation: "NewPassw0rd!x#9" } }
      expect(response).to redirect_to(settings_profile_path)
      expect(user.reload.password).to eq("NewPassw0rd!x#9")
      post login_authentication_path, params: { username_email: user.username, password: "NewPassw0rd!x#9" }
      expect(response).to have_http_status(:internal_server_error)
    end

    it "student identity requires program, faculty, year and student id" do
      login!(user)
      patch user_path(user.username), params: { user: { identity: "undergrad" } }
      expect(flash[:alert]).to include("Could not save changes.")
      expect(user.reload.identity).to eq("community_member")
    end

    it "rejects an out-of-range URL" do
      login!(user)
      patch user_path(user.username), params: { user: { url: "javascript:alert(1)" } }
      expect(flash[:alert]).to include("Url")
    end

    it "rejects html characters in the name" do
      login!(user)
      patch user_path(user.username), params: { user: { name: "<b>x</b>" } }
      expect(flash[:alert]).to include("must not contain special HTML characters")
    end
  end

  describe "avatar" do
    it "accepts a png upload" do
      login!(user)
      patch user_path(user.username), params: { user: { avatar: AvatarTestHelper.png } }
      expect(response).to redirect_to(settings_profile_path)
      expect(flash[:notice]).to eq("Profile updated successfully.")
      expect(user.reload.avatar).to be_attached
    end

    it "rejects a non-image upload with the validation message" do
      login!(user)
      patch user_path(user.username), params: { user: { avatar: AvatarTestHelper.stl } }
      expect(response).to redirect_to(settings_profile_path)
      expect(flash[:alert]).to start_with("Could not save changes.")
      expect(flash[:alert]).to include("Avatar")
      expect(user.reload.avatar).not_to be_attached
    end

    it "validates by declared content type only: an stl bytes file labelled image/png is accepted" do
      # WART(D-I17): avatar validation trusts the client-declared content type (file_content_type) so non-image bytes labelled image/png are stored
      login!(user)
      fake = Rack::Test::UploadedFile.new("spec/support/assets/test.stl", "image/png")
      patch user_path(user.username), params: { user: { avatar: fake } }
      expect(user.reload.avatar).to be_attached
    end

    it "GET /remove_avatar purges the avatar (state-changing GET)" do
      # WART(D-I18): remove_avatar is a state-changing GET (CSRF-able)
      login!(user)
      patch user_path(user.username), params: { user: { avatar: AvatarTestHelper.png } }
      get remove_avatar_users_path
      expect(response).to redirect_to(settings_profile_path)
      expect(user.reload.avatar).not_to be_attached
    end

    it "remove_avatar with no avatar is a harmless redirect" do
      login!(user)
      get remove_avatar_users_path
      expect(response).to redirect_to(settings_profile_path)
    end

    it "remove_avatar as guest redirects to login" do
      get remove_avatar_users_path
      expect(response.location).to start_with("http://www.example.com/login")
    end
  end

  describe "PATCH /:username/change_password" do
    let(:new_pw) { "NewPassw0rd!x#9" }

    def change!(old: password, pw: new_pw, confirm: pw)
      patch change_password_user_path(user.username),
            params: { user: { old_password: old, password: pw, password_confirmation: confirm } }
    end

    it "guest is redirected to login" do
      patch change_password_user_path(user.username), params: { user: { old_password: "x" } }
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "changes the password, emails the owner, redirects with notice" do
      login!(user)
      perform_enqueued_jobs { change! }
      expect(response).to redirect_to(settings_admin_path)
      expect(flash[:notice]).to eq("Password changed successfully, an email will be sent to confirm.")
      expect(user.reload.authenticate_password(new_pw)).to be(true)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([user.email])
      expect(deliveries.first.subject).to eq("MakerRepo | Your password has been changed")
    end

    it "wrong old password: re-renders settings/admin (200) with alert, unchanged" do
      login!(user)
      change!(old: "wrong")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Incorrect old password.")
      expect(user.reload.authenticate_password(password)).to be(true)
      expect(deliveries).to be_empty
    end

    it "mismatched confirmation: re-renders (200), unchanged" do
      login!(user)
      change!(confirm: "other")
      expect(response).to have_http_status(:ok)
      expect(user.reload.authenticate_password(password)).to be(true)
    end

    it "does not terminate other sessions or force re-login" do
      login!(user)
      change!
      get check_signed_in_path
      expect(json["signed_in"]).to eq("true")
    end
  end

  describe "flags (staff moderation)" do
    it "staff can flag, appending messages" do
      login!(staff)
      post flag_users_path, params: { flagged_user: user.id, flag_message: "late" }
      expect(response).to redirect_to(user_path(user.username))
      post flag_users_path, params: { flagged_user: user.id, flag_message: "again" }
      user.reload
      expect(user.flagged).to be(true)
      expect(user.flag_message).to eq("; late; again")
    end

    it "regular user cannot flag: redirected to own profile, nothing changes" do
      login!(other)
      post flag_users_path, params: { flagged_user: user.id, flag_message: "x" }
      expect(response).to redirect_to(user_path(other.username))
      expect(user.reload.flagged).to be_falsey
    end

    it "guest is redirected to login" do
      post flag_users_path, params: { flagged_user: user.id, flag_message: "x" }
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "staff can unflag; regular users cannot" do
      user.update_columns(flagged: true, flag_message: "; bad")
      login!(other)
      post unflag_users_path, params: { flagged_user: user.id }
      expect(user.reload.flagged).to be(true)
      login!(staff)
      post unflag_users_path, params: { flagged_user: user.id }
      expect(response).to redirect_to(user_path(user.username))
      user.reload
      expect(user.flagged).to be(false)
      expect(user.flag_message).to be_nil
    end

    it "any signed-in user can remove a flag message from any user" do
      # WART(D-I19): #remove_flag has no staff/admin check (flag/unflag do), so any signed-in user can clear anyone's moderation flags
      user.update_columns(flagged: true, flag_message: "; bad")
      login!(other)
      put remove_flag_users_path, params: { repo_user_id: user.id, flag_msg: "bad" }
      expect(response).to redirect_to(user_path(user.username))
      user.reload
      expect(user.flagged).to be(false)
      expect(user.flag_message).to eq("")
    end

    it "guest cannot remove a flag" do
      user.update_columns(flagged: true, flag_message: "; bad")
      put remove_flag_users_path, params: { repo_user_id: user.id, flag_msg: "bad" }
      expect(response.location).to start_with("http://www.example.com/login")
      expect(user.reload.flagged).to be(true)
    end
  end

  describe "POST /change_programs" do
    it "guest is redirected to login" do
      post change_programs_users_path, params: { user_id: user.id, volunteer: "1" }
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "regular user is refused with an alert" do
      login!(other)
      post change_programs_users_path, params: { user_id: user.id, volunteer: "1" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to start_with("An error occurred:")
      expect(user.programs).to be_empty
    end

    it "staff adds and removes programs" do
      login!(staff)
      post change_programs_users_path, params: { user_id: user.id, volunteer: "1", dev_program: "1" }
      expect(response).to redirect_to(user_path(user.username))
      expect(flash[:notice]).to eq("The programs for #{user.name} has been updated!")
      expect(user.programs.pluck(:program_type)).to match_array([Program::VOLUNTEER, Program::DEV_PROGRAM])
      post change_programs_users_path, params: { user_id: user.id, teams: "1" }
      expect(user.programs.reload.pluck(:program_type)).to eq([Program::TEAMS])
    end

    it "unknown user id: 404" do
      login!(staff)
      post change_programs_users_path, params: { user_id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /users/search" do
    before do
      create(:user, :regular_user, name: "Zebulon Quasar", username: "zebulonq")
    end

    it "guest gets the literal json string \"redirect\"" do
      get search_users_path, params: { search: "zebulon" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("redirect")
    end

    it "regular user gets usernames only" do
      login!(user)
      get search_users_path, params: { search: "zebulonq" }, as: :json
      expect(json["users"]).to eq([{ "username" => "zebulonq" }])
    end

    it "staff gets name and username" do
      login!(staff)
      get search_users_path, params: { search: "zebulonq" }, as: :json
      expect(json["users"]).to eq([{ "name" => "Zebulon Quasar", "username" => "zebulonq" }])
    end

    it "soft-deleted users never appear" do
      create(:user, :regular_user, name: "Deleted Dan", username: "deleteddan", deleted: true)
      login!(staff)
      get search_users_path, params: { search: "deleteddan" }, as: :json
      expect(json["users"]).to eq([])
    end

    it "inactive users do appear" do
      create(:user, :regular_user, name: "Inactive Ian", username: "inactiveian", active: false)
      login!(staff)
      get search_users_path, params: { search: "inactiveian" }, as: :json
      expect(json["users"].map { |u| u["username"] }).to include("inactiveian")
    end
  end

  describe "GET /:username/likes" do
    it "guest is redirected to login" do
      get likes_user_path(user.username)
      expect(response.location).to start_with("http://www.example.com/login")
    end

    it "lists the signed-in user's liked repos (path username is ignored)" do
      repo = create(:repository, user_id: other.id, title: "Liked Thing", share_type: "public")
      Like.create!(user_id: user.id, repository_id: repo.id)
      login!(user)
      get likes_user_path(other.username)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Liked Thing")
    end
  end

  describe "DELETE /:username (destroy)" do
    it "has no route: UsersController#destroy is unreachable" do
      login!(user)
      delete user_path(user.username)
      expect(response).to have_http_status(:not_found)
      expect(User.exists?(user.id)).to be(true)
    end
  end
end
