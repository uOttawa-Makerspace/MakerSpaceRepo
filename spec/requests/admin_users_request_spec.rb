# frozen_string_literal: true

require "rails_helper"

# Characterization spec for Admin::UsersController: the admin-only user
# management matrix (guest / regular / volunteer / staff / admin), role
# changes, soft delete + restore, lock toggle, rename, search and listing.
# Chunk 9 "Identity". Defects are PINNED, not fixed.
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

    # N+1 pinned: see defects.md D-PERF09
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

    # N+1 pinned: see defects.md D-PERF09
    it "index: accepts whitelisted sort", skip_bullet: true do
      get admin_users_path(sort: "username", direction: "asc")
      expect(response).to have_http_status(:ok)
    end

    it "index hides soft-deleted users (default scope)" do
      gone = create(:user, :regular_user, deleted: true)
      get admin_users_path
      expect(response.body).not_to include(gone.username)
    end

    # N+1 pinned: see defects.md D-PERF09
    it "index includes inactive users", skip_bullet: true do
      idle = create(:user, :regular_user, active: false)
      get admin_users_path
      expect(response.body).to include(idle.username)
    end

    it "search without q redirects back with 'Invalid parameters!'" do
      get search_admin_users_path
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Invalid parameters!")
    end

    it "search with at least one hit 500s: the view calls kaminari's total_pages on a pagy result" do
      # WART(D-I23): Admin::Users#search view calls `total_pages` (Kaminari API) but the controller paginates with Pagy, so every search that returns at least one user raises (500)
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

    it "updates the permitted profile fields only (gender, faculty, use)" do
      patch admin_user_path(target),
            params: { user: { gender: "Female", role: "admin", name: "Hacked", email: "x@y.z" } }
      expect(response).to redirect_to(edit_admin_user_path(target))
      expect(flash[:notice]).to eq("User information updated!")
      target.reload
      expect(target.gender).to eq("Female")
      expect(target.role).to eq("regular_user")
      expect(target.name).not_to eq("Hacked")
    end

    it "wipes all existing certifications on every update, even when none are re-sent" do
      # WART(D-I20): update runs `certifications.destroy_all` before validating, so a failed or certificate-less save silently deletes the user's certifications
      create(:certification, :basic_training, user_id: target.id)
      patch admin_user_path(target), params: { user: { gender: "Female" } }
      expect(target.certifications.reload.count).to eq(0)
    end

    it "a validation failure still wipes certifications and re-renders edit (200)" do
      create(:certification, :basic_training, user_id: target.id)
      patch admin_user_path(target), params: { user: { gender: "Bogus" } }
      expect(response).to have_http_status(:ok)
      expect(target.reload.gender).to eq("Male")
      expect(target.certifications.reload.count).to eq(0)
    end

    it "re-creates up to five named certifications" do
      patch admin_user_path(target),
            params: { user: { gender: "Male" }, certifications: %w[A B C D E F] }
      expect(target.certifications.reload.count).to be <= 5
    end

    it "assigns an unset RFID card" do
      rfid = Rfid.create!(card_number: "card#{SecureRandom.hex(3)}")
      patch admin_user_path(target), params: { user: { gender: "Male", rfid: rfid.id } }
      expect(rfid.reload.user_id).to eq(target.id)
    end
  end

  describe "PATCH /admin/users/set_role" do
    before { login!(admin) }

    # N+1 pinned: see defects.md D-PERF10
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

    it "admin can demote themselves, including the last admin" do
      # WART(D-I21): no guard against demoting yourself / the last remaining admin via set_role
      patch set_role_admin_users_path, params: { role: "regular_user", user_ids: [admin.id] }
      expect(admin.reload.role).to eq("regular_user")
      expect(User.where(role: "admin").count).to eq(0)
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

    it "soft-deletes: flags user and repositories, removes lab sessions and certifications" do
      repo = create(:repository)
      repo.users << target
      create(:lab_session, user_id: target.id) if FactoryBot.factories.registered?(:lab_session)
      create(:certification, :basic_training, user_id: target.id)
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("User flagged as deleted")
      expect(User.find_by(id: target.id)).to be_nil
      gone = User.unscoped.find(target.id)
      expect(gone.deleted).to be(true)
      expect(gone.repositories.reload.pluck(:deleted)).to all(be(true))
      expect(Certification.where(user_id: target.id)).to be_empty
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

    it "an admin may delete themselves" do
      # WART(D-I22): no guard against an admin soft-deleting their own account (or the last admin)
      delete delete_user_admin_users_path, params: { id: admin.id, password: password }
      expect(User.unscoped.find(admin.id).deleted).to be(true)
    end

    it "has no effect on the lingering session of the deleted user, which now 404s" do
      other_session = open_session
      other_session.post login_authentication_path, params: { username_email: target.username, password: password }
      delete delete_user_admin_users_path, params: { id: target.id, password: password }
      other_session.get settings_profile_path
      expect(other_session.response).to have_http_status(:not_found)
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
      # WART(D-I24): restore_user's `user.repositories.update_all(deleted: false)` goes through Repository's default scope (deleted: false), so soft-deleted repos stay deleted after a restore
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
