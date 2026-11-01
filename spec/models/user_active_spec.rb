# frozen_string_literal: true

require "rails_helper"

# `active` changes only through deactivate!/reactivate! (attr_readonly): they bump
# token_version in the same UPDATE, and deactivation keeps the last usable admin.
RSpec.describe User, "#active" do
  let(:user) { create(:user, :regular_user) }

  it "cannot be assigned on a persisted user: update(active: false) raises and leaves the column unchanged" do
    expect { user.update(active: false) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect(User.find(user.id).active).to be(true)
  end

  it "can still be set when the user is built" do
    expect(build(:user, active: false).active).to be(false)
  end

  describe "#deactivate!" do
    it "refuses to deactivate the last usable admin: raises LastAdminError and changes nothing" do
      admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: admin.id).update_all(active: false)
      version = admin.token_version

      expect { admin.deactivate! }.to raise_error(User::LastAdminError)
      expect(User.find(admin.id)).to have_attributes(active: true, token_version: version)
    end

    it "deactivates an admin while another usable admin remains" do
      admin = create(:user, :admin)
      create(:user, :admin)
      expect(admin.deactivate!).to be(true)
      expect(User.find(admin.id).active).to be(false)
    end

    it "is idempotent: a repeated call returns false, bumps nothing and revokes nothing" do
      expect(user.deactivate!).to be(true)
      version = User.find(user.id).token_version
      expect(ApiRefreshToken).not_to receive(:revoke_all_for!)
      expect(user.deactivate!).to be(false)
      expect(User.find(user.id)).to have_attributes(active: false, token_version: version)
    end

    it "does not refuse a no-op on an already inactive last admin" do
      admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: admin.id).update_all(active: false)
      User.where(id: admin.id).update_all(active: false)
      expect(admin.deactivate!).to be(false)
    end
  end

  describe "no-op syncs the instance" do
    it "deactivate! on a stale instance whose row is already inactive reports the stored active and token_version" do
      stale = User.find(user.id)
      User.where(id: user.id).update_all("active = false, token_version = token_version + 5")
      expect(stale.active).to be(true)
      expect(stale.deactivate!).to be(false)
      expect(stale.active).to be(false)
      expect(stale.token_version).to eq(User.find(user.id).token_version)
      expect(stale).not_to be_changed
    end

    it "reactivate! on a stale instance whose row is already active reports the stored active" do
      user.deactivate!
      stale = User.find(user.id)
      User.where(id: user.id).update_all("active = true, token_version = token_version + 1")
      expect(stale.reactivate!).to be(false)
      expect(stale.active).to be(true)
      expect(stale.token_version).to eq(User.find(user.id).token_version)
    end
  end

  describe "#deactivate! guard condition" do
    it "does not refuse deactivating a locked admin even when no other usable admin remains" do
      locked_admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: locked_admin.id).update_all(active: false)
      User.where(id: locked_admin.id).update_all(locked: true, locked_until: 99.years.from_now)
      expect(locked_admin.deactivate!).to be(true)
      expect(User.find(locked_admin.id).active).to be(false)
    end
  end

  describe "#reactivate!" do
    it "is idempotent: returns false and bumps nothing when already active" do
      version = user.token_version
      expect(ApiRefreshToken).not_to receive(:revoke_all_for!)
      expect(user.reactivate!).to be(false)
      expect(User.find(user.id).token_version).to eq(version)
    end

    it "reactivates an inactive user, returning true and bumping once" do
      user.deactivate!
      version = User.find(user.id).token_version
      expect(user.reactivate!).to be(true)
      expect(User.find(user.id)).to have_attributes(active: true, token_version: version + 1)
    end
  end
end
