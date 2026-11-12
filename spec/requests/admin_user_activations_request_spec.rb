# frozen_string_literal: true

require "rails_helper"

# Deactivating and reactivating an account from the admin user page.
RSpec.describe "Admin::Users::Activations", type: :request do
  let(:password) { "asa32A353#" }
  let(:admin) { create(:user, :admin) }
  let!(:other_admin) { create(:user, :admin) }
  let!(:target) { create(:user, :regular_user) }

  before { block_external_http! }

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
  end

  describe "DELETE /admin/users/:user_id/activation" do
    it "deactivates the account, keeps its data and ends its sessions" do
      target.update!(name: "Kept Name")
      version = target.token_version
      login!(admin)
      delete admin_user_activation_path(target)

      expect(response).to redirect_to(admin_user_path(target))
      expect(flash[:notice]).to eq(I18n.t("admin.users.activation.deactivated"))
      target.reload
      expect(target.deactivated_at).to be_present
      expect(target.token_version).to be > version
      expect(target.name).to eq("Kept Name")
      expect(target.deleted).to be(false)
    end

    it "says so when the account is already deactivated, changing nothing" do
      target.deactivate!
      version = target.reload.token_version
      login!(admin)
      delete admin_user_activation_path(target)

      expect(flash[:notice]).to eq(I18n.t("admin.users.activation.already_deactivated"))
      expect(target.reload.token_version).to eq(version)
    end

    it "refuses an admin deactivating their own account" do
      login!(admin)
      delete admin_user_activation_path(admin)

      expect(response).to redirect_to(admin_user_path(admin))
      expect(flash[:alert]).to eq(I18n.t("admin.users.activation.self_refused"))
      expect(admin.reload.deactivated_at).to be_nil
    end

    it "refuses deactivating the last usable admin" do
      login!(admin)
      admin.update_columns(locked: true, locked_until: 1.day.from_now)
      delete admin_user_activation_path(other_admin)

      expect(response).to redirect_to(admin_user_path(other_admin))
      expect(flash[:alert]).to eq(User::LAST_ADMIN_MESSAGE)
      expect(other_admin.reload.deactivated_at).to be_nil
    end

    it "bounces a non-admin and changes nothing" do
      login!(create(:user, :staff))
      delete admin_user_activation_path(target)
      expect(response).to redirect_to("/")
      expect(target.reload.deactivated_at).to be_nil
    end

    it "sends a guest to sign in" do
      delete admin_user_activation_path(target)
      expect_admin_area_bounce(guest: true)
      expect(target.reload.deactivated_at).to be_nil
    end
  end

  describe "POST /admin/users/:user_id/activation" do
    before { target.deactivate! }

    it "reactivates the account so the user can sign in again" do
      login!(admin)
      post admin_user_activation_path(target)

      expect(response).to redirect_to(admin_user_path(target))
      expect(flash[:notice]).to eq(I18n.t("admin.users.activation.reactivated"))
      expect(target.reload.deactivated_at).to be_nil

      reset!
      login!(target)
      expect(response).to have_http_status(:found).or have_http_status(:ok)
      get settings_profile_path
      expect(response).to have_http_status(:ok)
    end

    it "says so when the account is already active, changing nothing" do
      target.reactivate!
      version = target.reload.token_version
      login!(admin)
      post admin_user_activation_path(target)

      expect(flash[:notice]).to eq(I18n.t("admin.users.activation.already_active"))
      expect(target.reload.token_version).to eq(version)
    end

    it "bounces a non-admin and changes nothing" do
      login!(create(:user, :staff))
      post admin_user_activation_path(target)
      expect(response).to redirect_to("/")
      expect(target.reload.deactivated_at).to be_present
    end

    it "sends a guest to sign in" do
      post admin_user_activation_path(target)
      expect_admin_area_bounce(guest: true)
      expect(target.reload.deactivated_at).to be_present
    end
  end

  describe "a deactivated user" do
    it "cannot sign in" do
      target.deactivate!
      login!(target)
      get settings_profile_path
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "the admin user page" do
    it "offers deactivate for another user and reactivate once deactivated, never for oneself" do
      login!(admin)
      get admin_user_path(target)
      expect(response.body).to include(I18n.t("admin.users.show.deactivate"))

      get admin_user_path(admin)
      expect(response.body).not_to include(I18n.t("admin.users.show.deactivate"))

      target.deactivate!
      get admin_user_path(target)
      expect(response.body).to include(I18n.t("admin.users.show.reactivate"))
    end
  end
end
