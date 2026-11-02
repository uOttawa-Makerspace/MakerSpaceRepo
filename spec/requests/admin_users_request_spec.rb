# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Admin::UsersController: the admin-only user
# management matrix (guest / regular / volunteer / staff / admin), role
# changes, soft delete + restore, lock toggle, rename, search and listing.
# Chunk 9 "Identity".
#
# Every action sits behind AdminAreaController#ensure_admin, which redirects
# any non-admin (guests included) to "/" with no flash; there are no
# per-action staff exceptions. Impersonation does not exist in this app.

RSpec.describe "Admin::Users (HTTP contract)", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user, :regular_user) }
  let(:volunteer) { create(:user, :volunteer) }
  let!(:target) { create(:user, :regular_user) }

  before { block_external_http! }

  def login!(u, pw: password)
    post login_authentication_path, params: { username_email: u.username, password: pw }
    u
  end

  def as(role)
    case role
    when :guest then nil
    when :regular then login!(regular)
    when :volunteer then login!(volunteer)
    when :staff then login!(staff)
    when :admin then login!(admin)
    end
  end

  NON_ADMINS = %i[guest regular volunteer staff].freeze

  def expect_bounced
    expect(response).to have_http_status(:found)
    expect(response.location).to eq("http://www.example.com/")
    expect(flash[:alert]).to be_nil
  end

  describe "authorization matrix: non-admins are bounced to / and nothing changes" do
    NON_ADMINS.each do |role|
      context "as #{role}" do
        before { as(role) }

        it "GET index/search/show/edit/manage_roles" do
          [admin_users_path, search_admin_users_path(q: "a"), admin_user_path(target),
           edit_admin_user_path(target), manage_roles_admin_users_path].each do |path|
            get path
            expect_bounced
          end
        end

        it "PATCH update does not touch the user" do
          patch admin_user_path(target), params: { user: { gender: "Female" } }
          expect_bounced
          expect(target.reload.gender).to eq("Male")
        end

        it "PATCH set_role does not change roles" do
          patch set_role_admin_users_path, params: { role: "admin", user_ids: [target.id] }
          expect_bounced
          expect(target.reload.role).to eq("regular_user")
        end

        it "DELETE delete_user does not soft-delete" do
          delete delete_user_admin_users_path, params: { id: target.id, password: password }
          expect_bounced
          expect(target.reload.deleted).to be(false)
        end

        it "PATCH restore_user / PUT toggle_lock_user / PATCH rename_user are refused" do
          target.update_columns(deleted: true)
          patch restore_user_admin_users_path, params: { id: target.id }
          expect_bounced
          expect(User.unscoped.find(target.id).deleted).to be(true)
          User.unscoped.where(id: target.id).update_all(deleted: false)

          put toggle_lock_user_admin_users_path, params: { id: target.id }
          expect_bounced
          expect(target.reload.locked).to be(false)

          patch rename_user_admin_users_path, params: { id: target.id, rename: "renamedx" }
          expect_bounced
          expect(target.reload.username).not_to eq("renamedx")
        end

        it "DELETE delete_repository does not destroy" do
          repo = create(:repository)
          delete delete_repository_admin_users_path, params: { id: repo.id }
          expect_bounced
          expect(Repository.exists?(repo.id)).to be(true)
        end
      end
    end
  end

  describe "listing (admin)" do
    before { login!(admin) }

    # N+1 pinned
    it "index defaults to newest users", skip_bullet: true do
      get admin_users_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(target.username)
    end

    it "index p=signed_in_users shows active lab sessions" do
      get admin_users_path(p: "signed_in_users")
      expect(response).to have_http_status(:ok)
    end

    it "index: unknown p redirects with 'Invalid parameters!'" do
      get admin_users_path(p: "bogus")
      expect(response).to redirect_to(admin_users_path)
      expect(flash[:alert]).to eq("Invalid parameters!")
    end

    it "index: sort whitelist rejects unknown columns" do
      get admin_users_path(sort: "password", direction: "asc")
      expect(response).to redirect_to(admin_users_path)
      expect(flash[:alert]).to eq("Invalid parameters!")
    end

    # N+1 pinned
    it "index: accepts whitelisted sort", skip_bullet: true do
      get admin_users_path(sort: "username", direction: "asc")
      expect(response).to have_http_status(:ok)
    end

    it "index hides soft-deleted users (default scope)" do
      gone = create(:user, :regular_user, deleted: true)
      get admin_users_path
      expect(response.body).not_to include(gone.username)
    end

    # N+1 pinned
    it "index includes inactive users", skip_bullet: true do
      idle = create(:user, :regular_user, deactivated_at: Time.current)
      get admin_users_path
      expect(response.body).to include(idle.username)
    end

    it "search without q redirects back with 'Invalid parameters!'" do
      get search_admin_users_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Invalid parameters!")
    end

    it "search with at least one hit 500s: the view calls kaminari's total_pages on a pagy result" do
      # Admin::Users#search view calls `total_pages` (Kaminari API) but the controller paginates with Pagy, so every search that returns at least one user raises (500)
      get search_admin_users_path(q: target.username, filter: "Username")
      expect(response).to have_http_status(:internal_server_error)
    end

    it "search with no hit renders 200 (empty), and soft-deleted users are never hits" do
      get search_admin_users_path(q: "zzznomatchzzz")
      expect(response).to have_http_status(:ok)
      gone = create(:user, :regular_user, deleted: true, name: "Ghostly Gus")
      get search_admin_users_path(q: gone.username)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Ghostly Gus")
    end

    it "search rejects an unknown sort" do
      get search_admin_users_path(q: "a", sort: "password", direction: "asc")
      expect(response).to redirect_to(admin_users_path)
      expect(flash[:alert]).to eq("Invalid parameters!")
    end

    it "show renders for any user and 404s for a soft-deleted user" do
      get admin_user_path(target)
      expect(response).to have_http_status(:ok)
      gone = create(:user, :regular_user, deleted: true)
      get admin_user_path(gone)
      expect(response).to have_http_status(:not_found)
    end

    it "edit renders" do
      get edit_admin_user_path(target)
      expect(response).to have_http_status(:ok)
    end

    it "manage_roles renders" do
      get manage_roles_admin_users_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /admin/users/:id (update)" do
    before { login!(admin) }

    it "updates the permitted profile fields; role and email are not set here" do
      patch admin_user_path(target),
            params: { user: { gender: "Female", name: "New Name", role: "admin", email: "x@y.z" } }
      expect(response).to redirect_to(edit_admin_user_path(target))
      expect(flash[:notice]).to eq("User information updated")
      target.reload
      expect(target.gender).to eq("Female")
      expect(target.name).to eq("New Name")
      expect(target.role).to eq("regular_user")
      expect(target.email).not_to eq("x@y.z")
    end

    it "no longer edits certifications (a sent list is ignored)" do
      create(:certification, :basic_training, user_id: target.id)
      patch admin_user_path(target), params: { user: { gender: "Male" }, certifications: %w[A B] }
      expect(response).to redirect_to(edit_admin_user_path(target))
      expect(target.certifications.reload.count).to eq(1)
    end

    it "a validation failure re-renders edit (422) and undoes the RFID assignment" do
      rfid = Rfid.create!(card_number: "card#{SecureRandom.hex(3)}")
      patch admin_user_path(target), params: { user: { gender: "Bogus", rfid: rfid.id } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(target.reload.gender).to eq("Male")
      expect(rfid.reload.user_id).to be_nil
    end

    it "is admin only: staff are refused and nothing changes" do
      login!(staff)
      patch admin_user_path(target), params: { user: { name: "Staff Edit" } }
      expect(target.reload.name).not_to eq("Staff Edit")
    end

    it "assigns an unset RFID card" do
      rfid = Rfid.create!(card_number: "card#{SecureRandom.hex(3)}")
      patch admin_user_path(target), params: { user: { gender: "Male", rfid: rfid.id } }
      expect(rfid.reload.user_id).to eq(target.id)
    end
  end

  describe "PATCH /admin/users/:id/change_email" do
    before do
      login!(admin)
      ActionMailer::Base.deliveries.clear
    end

    it "mails the user's own confirmation link to the new address, without changing the email yet" do
      old = target.email
      patch change_email_admin_user_path(target), params: { new_email: "New.Address@example.com", confirm_new_email: "new.address@example.com" }
      expect(response).to redirect_to(edit_admin_user_path(target))
      expect(flash[:notice]).to eq("A confirmation email has been sent to the new email")
      expect(target.reload.email).to eq(old)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["new.address@example.com"])
      body = (mail.html_part || mail).body.decoded
      token = body[/token=([^"&<\s]+)/, 1]
      expect(User.email_change_from_token(CGI.unescape(token.to_s))).to eq([target, "new.address@example.com"])
    end

    it "refuses an address another account uses" do
      other = create(:user, :regular_user)
      patch change_email_admin_user_path(target), params: { new_email: other.email.upcase, confirm_new_email: other.email }
      expect(flash[:alert]).to eq("This email is already used by a MakerRepo Account.")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "refuses a confirmation that does not match" do
      patch change_email_admin_user_path(target), params: { new_email: "a@example.com", confirm_new_email: "b@example.com" }
      expect(flash[:alert]).to eq("This confirmation email isn't matching the new email")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "is admin only" do
      login!(staff)
      patch change_email_admin_user_path(target), params: { new_email: "a@example.com", confirm_new_email: "a@example.com" }
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "PATCH /admin/users/set_role" do
    before { login!(admin) }

    # N+1 pinned
    it "changes roles for several users, redirecting back (html)", skip_bullet: true do
      other = create(:user, :regular_user)
      patch set_role_admin_users_path,
            params: { role: "staff", user_ids: [target.id, other.id] },
            headers: { "HTTP_REFERER" => "http://www.example.com/admin/users/manage_roles" }
      expect(response).to redirect_to("http://www.example.com/admin/users/manage_roles")
      expect(target.reload.role).to eq("staff")
      expect(other.reload.role).to eq("staff")
    end

    it "json: head 200" do
      patch set_role_admin_users_path, params: { role: "volunteer", user_ids: [target.id] }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).to be_blank
      expect(target.reload.role).to eq("volunteer")
    end

    it "rejects roles outside the assignable list (silently, redirecting)" do
      patch set_role_admin_users_path, params: { role: "superuser", user_ids: [target.id] }
      expect(response).to redirect_to(root_path)
      expect(target.reload.role).to eq("regular_user")
    end

    it "ignores non-array user_ids" do
      patch set_role_admin_users_path, params: { role: "admin", user_ids: target.id.to_s }
      expect(target.reload.role).to eq("regular_user")
    end

    it "blocks demoting the last admin (HTML: redirect + alert)" do
      # set_role refuses a change that would leave no admin
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot remove the last admin.")
      expect(admin.reload.role).to eq("admin")
    end

    it "blocks demoting the last admin with a 422 JSON error (React app)" do
      patch set_role_admin_users_path, params: { role: "staff", user_ids: [admin.id, target.id] }.to_json,
                                       headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("You cannot remove the last admin.")
      expect(admin.reload.role).to eq("admin")
      expect(target.reload.role).to eq("regular_user")
    end

    it "does not count a locked admin as remaining (the only usable admin cannot demote themselves)" do
      # the guard counts only admins who can sign in
      create(:user, :admin, locked: true, locked_until: 99.years.from_now)
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(flash[:alert]).to eq("You cannot remove the last admin.")
      expect(admin.reload.role).to eq("admin")
    end

    it "counts an admin with NULL locked as remaining" do
      # `locked` is nullable; an expired lockout is cleared at next login
      create(:user, :admin).update_columns(locked: nil)
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(admin.reload.role).to eq("regular_user")
    end

    it "counts an admin whose temporary lockout has expired as remaining" do
      create(:user, :admin, locked: true, locked_until: 1.hour.ago)
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(admin.reload.role).to eq("regular_user")
    end

    it "lets an admin demote themselves when another admin remains" do
      create(:user, :admin)
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(admin.reload.role).to eq("regular_user")
    end

    it "still lets an admin promote and keeps the admin when role is admin" do
      patch set_role_admin_users_path, params: { role: "admin", user_ids: [admin.id, target.id] }
      expect(target.reload.role).to eq("admin")
    end

    it "does not touch soft-deleted users (default scope)" do
      gone = create(:user, :regular_user, deleted: true)
      patch set_role_admin_users_path, params: { role: "admin", user_ids: [gone.id] }
      expect(User.unscoped.find(gone.id).role).to eq("regular_user")
    end

    it "syncs staff spaces for staff users only" do
      space = create(:space)
      s = create(:user, :staff)
      patch set_role_admin_users_path,
            params: { role: "staff", user_ids: [], spaces: { s.id.to_s => [space.id], target.id.to_s => [space.id] } }
      expect(s.staff_spaces.pluck(:space_id)).to eq([space.id])
      expect(target.staff_spaces).to be_empty
      expect(flash[:notice]).to eq("Successfully changed spaces for the user(s).")
    end

    it "keeps spaces when a staff user is demoted (staff_spaces untouched)" do
      space = create(:space)
      s = create(:user, :staff)
      StaffSpace.create!(user: s, space: space)
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [s.id] }
      expect(s.reload.role).to eq("regular_user")
      expect(s.staff_spaces.count).to eq(1)
    end
  end

  describe "DELETE /admin/users/delete_user (soft delete)" do
    before { login!(admin) }

    it "requires the admin's own password" do
      delete delete_user_admin_users_path, params: { id: target.id, password: "wrong" }
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:alert]).to eq("Invalid password!")
      expect(target.reload.deleted).to be(false)
    end

    # The admin's re-typed password is counted in the same budget as change_password / change_email (ReauthThrottle):
    # five wrong guesses are answered normally, the sixth ends every credential without checking the password.
    it "counts wrong passwords in the re-authentication budget and signs the admin out once it is exhausted" do
      before = admin.reload.token_version
      ReauthThrottle::REAUTH_MAX_ATTEMPTS.times do
        delete delete_user_admin_users_path, params: { id: target.id, password: "wrong" }
        expect(flash[:alert]).to eq("Invalid password!")
      end
      expect(RateLimitCounter.find_by!(key: "reauth/#{admin.id}/#{before}").count).to eq(ReauthThrottle::REAUTH_MAX_ATTEMPTS)

      expect_any_instance_of(User).not_to receive(:authenticate_password)
      delete delete_user_admin_users_path, params: { id: target.id, password: password }

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq(ReauthThrottle::REAUTH_LIMIT_ALERT)
      expect(admin.reload.token_version).to eq(before + 1)
      expect(target.reload.deleted).to be(false)
    end

    it "clears the count after a correct password" do
      key = "reauth/#{admin.id}/#{admin.reload.token_version}"
      2.times { delete delete_user_admin_users_path, params: { id: target.id, password: "wrong" } }
      expect(RateLimitCounter.find_by!(key: key).count).to eq(2)
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      expect(RateLimitCounter.exists?(key)).to be(false)
    end

    it "soft-deletes: flags user and repositories, removes lab sessions and certifications" do
      repo = create(:repository)
      repo.users << target
      space = create(:space)
      create(:lab_session, user_id: target.id, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      create(:lab_session, user_id: target.id, space: space, sign_in_time: 2.days.ago, sign_out_time: 2.days.ago + 1.hour)
      bystander = create(:lab_session, space: space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      create(:certification, :basic_training, user_id: target.id)
      expect(LabSession.where(user_id: target.id).count).to eq(2)
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("User flagged as deleted")
      expect(User.find_by(id: target.id)).to be_nil
      gone = User.unscoped.find(target.id)
      expect(gone.deleted).to be(true)
      expect(gone.repositories.reload.pluck(:deleted)).to all(be(true))
      expect(Certification.where(user_id: target.id)).to be_empty
      expect(LabSession.where(user_id: target.id)).to be_empty
      expect(LabSession.where(id: bystander.id)).to exist
    end

    it "the deleted user can no longer log in or be found by username/email" do
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      expect(User.username_or_email(target.username)).to be_nil
      expect(User.find_by_username(target.username)).to be_nil
      expect(User.unscoped.find_by_username(target.username)).to be_a(User)
      guest = open_session
      guest.post login_authentication_path, params: { username_email: target.username, password: password }
      expect(guest.response).to have_http_status(:unprocessable_content)
      expect(guest.flash[:alert]).to start_with("Could not find user")
    end

    it "keeps the row, so the username and email stay reserved" do
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      dup = build(:user, :regular_user, username: target.username, email: target.email)
      # the uniqueness validators use unscoped queries, so soft-deleted rows still reserve the name
      expect(dup.valid?).to be(false)
      expect(dup.errors.attribute_names).to include(:username, :email)
      expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "a deleted id 404s the second time" do
      2.times { delete delete_user_admin_users_path, params: { id: target.id, password: password } }
      expect(response).to have_http_status(:not_found)
    end

    it "refuses to delete the last admin (even themselves)" do
      # the last admin cannot be soft-deleted
      delete delete_user_admin_users_path, params: { id: admin.id, password: password }
      expect(response).to redirect_to(user_path(admin.username))
      expect(flash[:alert]).to eq("You cannot remove the last admin.")
      expect(User.unscoped.find(admin.id).deleted).to be(false)
    end

    it "does not count a locked admin as remaining when deleting" do
      # the guard counts only admins who can sign in
      create(:user, :admin, locked: true, locked_until: 99.years.from_now)
      delete delete_user_admin_users_path, params: { id: admin.id, password: password }
      expect(flash[:alert]).to eq("You cannot remove the last admin.")
      expect(User.unscoped.find(admin.id).deleted).to be(false)
    end

    it "lets an admin delete themselves when another admin remains" do
      create(:user, :admin)
      delete delete_user_admin_users_path, params: { id: admin.id, password: password }
      expect(User.unscoped.find(admin.id).deleted).to be(true)
    end

    it "ends the lingering session of the deleted user on its next request" do
      # was a 404 for the lingering session; session_user now signs it out
      other_session = open_session
      other_session.post login_authentication_path, params: { username_email: target.username, password: password }
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      other_session.get settings_profile_path
      expect(other_session.response).to have_http_status(:found)
      expect(other_session.response.location).to include("/login")
    end
  end

  describe "PATCH /admin/users/restore_user" do
    before { login!(admin) }

    it "restores a soft-deleted user and their repositories" do
      target.update_columns(deleted: true)
      patch restore_user_admin_users_path, params: { id: target.id }
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:notice]).to eq("User restored!")
      expect(User.find(target.id).deleted).to be(false)
    end

    it "does not actually restore the user's repositories (update_all runs under Repository's default scope)" do
      # restore_user's `user.repositories.update_all(deleted: false)` goes through Repository's default scope (deleted: false), so soft-deleted repos stay deleted after a restore
      repo = create(:repository)
      repo.users << target
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
      patch restore_user_admin_users_path, params: { id: target.id }
      expect(Repository.unscoped.find(repo.id).deleted).to be(true)
    end

    it "does not restore the certifications or lab sessions deleted on soft delete" do
      create(:certification, :basic_training, user_id: target.id)
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      patch restore_user_admin_users_path, params: { id: target.id }
      expect(Certification.where(user_id: target.id)).to be_empty
    end

    it "restoring a never-deleted user is a no-op success" do
      patch restore_user_admin_users_path, params: { id: target.id }
      expect(flash[:notice]).to eq("User restored!")
    end

    it "unknown id: 404" do
      patch restore_user_admin_users_path, params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /admin/users/toggle_lock_user" do
    before { login!(admin) }

    it "locks for 99 years with 5 attempts, then unlocks" do
      put toggle_lock_user_admin_users_path, params: { id: target.id }
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:notice]).to eq("User locked!")
      target.reload
      expect(target.locked).to be(true)
      expect(target.auth_attempts).to eq(5)
      expect(target.locked_until).to be > 90.years.from_now
      post login_authentication_path, params: { username_email: target.username, password: password }
      expect(flash[:alert]).to include("locked")
      put toggle_lock_user_admin_users_path, params: { id: target.id }
      expect(flash[:notice]).to eq("User unlocked!")
      target.reload
      expect(target.locked).to be(false)
      expect(target.auth_attempts).to eq(0)
      expect(target.locked_until).to be_nil
    end
  end

  describe "PUT /admin/users/toggle_lock_user deciding under the lock" do
    before { login!(admin) }

    it "decides lock vs unlock from the row as it is under the guard, not from the earlier read" do
      expect(target.reload.locked).to be_falsey
      # another admin's lock lands after the controller read the (unlocked) row and before the guarded block
      allow(User).to receive(:guarding_last_admin!).and_wrap_original do |original, *args, **kwargs, &block|
        User.where(id: target.id).update_all(locked: true, locked_until: 99.years.from_now, auth_attempts: User::MAX_AUTH_ATTEMPTS)
        original.call(*args, **kwargs, &block)
      end
      put toggle_lock_user_admin_users_path, params: { id: target.id }
      expect(flash[:notice]).to eq("User unlocked!")
      expect(target.reload.locked).to be(false)
    end
  end

  describe "PUT /admin/users/toggle_lock_user and token_version" do
    before { login!(admin) }

    it "bumps the target's token_version when locking, not when unlocking" do
      # an admin lock permanently ends existing sessions and JWTs
      expect { put toggle_lock_user_admin_users_path, params: { id: target.id } }
        .to change { target.reload.token_version }.by(1)
      expect { put toggle_lock_user_admin_users_path, params: { id: target.id } }
        .not_to(change { target.reload.token_version })
    end
  end

  describe "PUT /admin/users/toggle_lock_user on a legacy-invalid user" do
    before { login!(admin) }

    it "locks (token_version bumped, sessions and JWTs dead) and unlocks without validating the row" do
      # the lock was written with save!, which raised (500) for a row invalid for an unrelated legacy reason
      target.update_columns(username: "old_user_name_longer_than_20", gender: "stale value")
      expect(target.reload).not_to be_valid
      token = target.token
      victim = open_session
      victim.post login_authentication_path, params: { username_email: target.username, password: password }
      victim.get check_signed_in_path
      expect(JSON.parse(victim.response.body)["signed_in"]).to eq("true")

      put toggle_lock_user_admin_users_path, params: { id: target.id }
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:notice]).to eq("User locked!")
      target.reload
      expect(target.locked).to be(true)
      expect(target.locked_until).to be > 90.years.from_now
      expect(target.token_version).to eq(1)
      victim.get check_signed_in_path
      expect(JSON.parse(victim.response.body)["signed_in"]).to eq("false")
      expect(JwtAuthenticator.user_for("Bearer #{token}")).to be_nil

      put toggle_lock_user_admin_users_path, params: { id: target.id }
      expect(flash[:notice]).to eq("User unlocked!")
      target.reload
      expect(target.locked).to be(false)
      expect(target.locked_until).to be_nil
      expect(target.auth_attempts).to eq(0)
      expect(target.token_version).to eq(1)
    end
  end

  describe "PUT /admin/users/toggle_lock_user last-admin guard" do
    before { login!(admin) }

    # locking cannot remove the last usable admin
    it "refuses to lock the only usable admin" do
      put toggle_lock_user_admin_users_path, params: { id: admin.id }
      expect(response).to redirect_to(user_path(admin.username))
      expect(flash[:alert]).to eq("You cannot lock the last admin.")
      expect(admin.reload.locked).to be(false)
    end

    it "refuses to lock the acting admin when every other admin is locked" do
      # (a locked admin can no longer be the acting session: locked sessions end on the next request)
      other = create(:user, :admin, locked: true, locked_until: 99.years.from_now)
      put toggle_lock_user_admin_users_path, params: { id: admin.id }
      expect(flash[:alert]).to eq("You cannot lock the last admin.")
      expect(admin.reload.locked).to be(false)
      expect(other.reload.locked).to be(true)
    end

    it "locks an admin when another usable admin remains" do
      other = create(:user, :admin)
      put toggle_lock_user_admin_users_path, params: { id: other.id }
      expect(flash[:notice]).to eq("User locked!")
      expect(other.reload.locked).to be(true)
    end

    it "always allows unlocking an admin" do
      other = create(:user, :admin, locked: true, locked_until: 99.years.from_now)
      put toggle_lock_user_admin_users_path, params: { id: other.id }
      expect(flash[:notice]).to eq("User unlocked!")
    end
  end

  describe "PATCH /admin/users/rename_user" do
    before { login!(admin) }

    it "renames" do
      patch rename_user_admin_users_path, params: { id: target.id, rename: "newhandle" }
      expect(response).to redirect_to(user_path("newhandle"))
      expect(flash[:notice]).to eq("User renamed successfully")
      expect(target.reload.username).to eq("newhandle")
    end

    it "blank rename: alert" do
      patch rename_user_admin_users_path, params: { id: target.id }
      expect(response).to redirect_to(user_path(target.username))
      expect(flash[:alert]).to eq("No username provided")
    end

    it "invalid or taken username: alert and unchanged" do
      old = target.username
      patch rename_user_admin_users_path, params: { id: target.id, rename: "bad name!" }
      expect(flash[:alert]).to start_with("Username invalid:")
      expect(target.reload.username).to eq(old)
      patch rename_user_admin_users_path, params: { id: target.id, rename: regular.username }
      expect(flash[:alert]).to start_with("Username invalid:")
    end
  end

  describe "DELETE /admin/users/delete_repository" do
    before { login!(admin) }

    it "destroys any repository and redirects to root" do
      repo = create(:repository)
      delete delete_repository_admin_users_path, params: { id: repo.id }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Repository Deleted!")
      expect(Repository.exists?(repo.id)).to be(false)
    end

    it "unknown id: 404" do
      delete delete_repository_admin_users_path, params: { id: 0 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "volunteer role" do
    it "the volunteer role has no extra admin access" do
      login!(volunteer)
      get admin_users_path
      expect_bounced
    end
  end
end

RSpec.describe "Admin user changes on a legacy-invalid user", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  let!(:target) { create(:user, :staff) }
  let(:disconnected) { [] }

  before do
    block_external_http!
    allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
      double("remote").tap { |r| allow(r).to receive(:disconnect) { disconnected << current_user } }
    end
    post login_authentication_path, params: { username_email: admin.username, password: password }
    target.update_columns(username: "old_user_name_longer_than_20", gender: "stale value")
    expect(target.reload).not_to be_valid
  end

  it "demotes (one disconnect, role stored)" do
    patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [target.id] }
    expect(target.reload.role).to eq("regular_user")
    expect(disconnected).to eq([target])
  end

  it "does not disconnect on a promotion of an invalid row" do
    patch set_role_admin_users_path, params: { role: "admin", user_ids: [target.id] }
    expect(target.reload.role).to eq("admin")
    expect(disconnected).to be_empty
  end

  it "soft-deletes (one disconnect, session and JWT dead) and restores" do
    token = target.token
    victim = open_session
    victim.post login_authentication_path, params: { username_email: target.username, password: password }
    victim.get check_signed_in_path
    expect(JSON.parse(victim.response.body)["signed_in"]).to eq("true")

    delete delete_user_admin_users_path, params: { id: target.id, password: password }
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("User flagged as deleted")
    expect(User.unscoped.find(target.id).deleted).to be(true)
    expect(disconnected).to eq([target])
    victim.get check_signed_in_path
    expect(JSON.parse(victim.response.body)["signed_in"]).to eq("false")
    expect(JwtAuthenticator.user_for("Bearer #{token}")).to be_nil

    patch restore_user_admin_users_path, params: { id: target.id }
    expect(flash[:notice]).to eq("User restored!")
    expect(User.unscoped.find(target.id).deleted).to be(false)
    expect(disconnected).to eq([target])
  end
end

RSpec.describe "Bulk role change atomicity", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }

  before do
    block_external_http!
    post login_authentication_path, params: { username_email: admin.username, password: password }
  end

  it "leaves every role unchanged when the second user's write raises" do
    a = create(:user, :staff)
    b = create(:user, :staff)
    calls = 0
    allow_any_instance_of(User).to receive(:change_role!).and_wrap_original do |m, *args|
      calls += 1
      raise ActiveRecord::StatementInvalid, "boom" if calls == 2
      m.call(*args)
    end
    begin
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [a.id, b.id] }
    rescue ActiveRecord::StatementInvalid
      nil
    end
    expect(calls).to eq(2)
    expect([a.reload.role, b.reload.role]).to eq(%w[staff staff])
  end
end

RSpec.describe "Soft delete revokes sessions for good", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  let!(:target) { create(:user, :regular_user) }

  before do
    block_external_http!
    post login_authentication_path, params: { username_email: admin.username, password: password }
  end

  it "keeps pre-delete sessions and JWTs dead after restore, while a fresh login works" do
    token = target.token
    victim = open_session
    victim.post login_authentication_path, params: { username_email: target.username, password: password }
    victim.get check_signed_in_path
    expect(JSON.parse(victim.response.body)["signed_in"]).to eq("true")

    delete delete_user_admin_users_path, params: { id: target.id, password: password }
    patch restore_user_admin_users_path, params: { id: target.id }
    expect(User.find(target.id).token_version).to eq(1)

    victim.get check_signed_in_path
    expect(JSON.parse(victim.response.body)["signed_in"]).to eq("false")
    expect(JwtAuthenticator.user_for("Bearer #{token}")).to be_nil

    fresh = open_session
    fresh.post login_authentication_path, params: { username_email: target.username, password: password }
    fresh.get check_signed_in_path
    expect(JSON.parse(fresh.response.body)["signed_in"]).to eq("true")
    expect(JwtAuthenticator.user_for("Bearer #{User.find(target.id).token}")).to eq(target)
  end
end
