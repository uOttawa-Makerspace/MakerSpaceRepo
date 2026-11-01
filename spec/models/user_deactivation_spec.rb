# frozen_string_literal: true

require "rails_helper"

# `deactivated_at` (NULL = not deactivated) changes only through deactivate!/reactivate!
# (attr_readonly): they bump token_version in the same UPDATE, and deactivation keeps the
# last usable admin. The legacy `active` column (2021-22 dormancy snapshot) is never read
# or written by any of it.
RSpec.describe User, "#deactivated_at" do
  let(:user) { create(:user, :regular_user) }

  def legacy_inactive!(*users)
    User.where(id: users.map(&:id)).update_all(active: false)
  end

  it "cannot be assigned on a persisted user: update(deactivated_at:) raises and leaves the column unchanged" do
    expect { user.update(deactivated_at: Time.current) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect { user.deactivated_at = Time.current }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect(User.find(user.id).deactivated_at).to be_nil
  end

  it "keeps the legacy active column readonly too: update(active:) raises and leaves it unchanged" do
    expect { user.update(active: false) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    expect(User.find(user.id).active).to be(true)
  end

  it "can still be set when the user is built" do
    expect(build(:user, deactivated_at: Time.current).deactivated_at).to be_present
  end

  it "is NULL for a new user" do
    expect(user.deactivated_at).to be_nil
  end

  describe ".not_deactivated" do
    it "includes legacy active = false users and excludes deactivated ones" do
      legacy = create(:user, :regular_user)
      legacy_inactive!(legacy)
      gone = create(:user, :regular_user)
      gone.deactivate!
      ids = User.not_deactivated.where(id: [user.id, legacy.id, gone.id]).pluck(:id)
      expect(ids).to contain_exactly(user.id, legacy.id)
    end
  end

  describe "AuthEligibility" do
    it "refuses a deactivated user and allows one with legacy active = false" do
      legacy_inactive!(user)
      expect(AuthEligibility.allowed?(User.find(user.id))).to be(true)
      user.deactivate!
      expect(AuthEligibility.allowed?(User.find(user.id))).to be(false)
    end
  end

  describe "#deactivate!" do
    it "sets deactivated_at and bumps token_version in one UPDATE, without writing active" do
      version = user.token_version
      expect { expect(user.deactivate!).to be(true) }.not_to(change { User.find(user.id).active })
      row = User.find(user.id)
      expect(row.deactivated_at).to be_within(1.minute).of(Time.current)
      expect(row.token_version).to eq(version + 1)
      expect(user).not_to be_changed
      expect(user.deactivated_at).to eq(row.deactivated_at)
    end

    it "does not write active when the legacy value is false either" do
      legacy_inactive!(user)
      user.deactivate!
      expect(User.find(user.id)).to have_attributes(active: false, deactivated_at: be_present)
    end

    it "refuses to deactivate the last usable admin: raises LastAdminError and changes nothing" do
      admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: admin.id).update_all(deactivated_at: Time.current)
      version = admin.token_version

      expect { admin.deactivate! }.to raise_error(User::LastAdminError)
      expect(User.find(admin.id)).to have_attributes(deactivated_at: nil, token_version: version)
    end

    it "deactivates an admin while another usable admin remains" do
      admin = create(:user, :admin)
      create(:user, :admin)
      expect(admin.deactivate!).to be(true)
      expect(User.find(admin.id).deactivated_at).to be_present
    end

    it "counts an admin with legacy active = false as usable, so deactivating the other admin is refused" do
      legacy_admin = create(:user, :admin)
      other = create(:user, :admin)
      User.where(role: "admin").where.not(id: [legacy_admin.id, other.id]).update_all(deactivated_at: Time.current)
      legacy_inactive!(legacy_admin)

      expect(User.usable_admins).to include(legacy_admin)
      expect(other.deactivate!).to be(true) # legacy_admin still stands
      expect { legacy_admin.deactivate! }.to raise_error(User::LastAdminError)
    end

    it "is idempotent: a repeated call returns false, bumps nothing, keeps the time and revokes nothing" do
      expect(user.deactivate!).to be(true)
      row = User.find(user.id)
      expect(ApiRefreshToken).not_to receive(:revoke_all_for!)
      expect(user.deactivate!).to be(false)
      expect(User.find(user.id)).to have_attributes(deactivated_at: row.deactivated_at, token_version: row.token_version)
    end

    it "does not refuse a no-op on an already deactivated last admin" do
      admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: admin.id).update_all(deactivated_at: Time.current)
      User.where(id: admin.id).update_all(deactivated_at: Time.current)
      expect(admin.deactivate!).to be(false)
    end

    it "does not refuse deactivating a locked admin even when no other usable admin remains" do
      locked_admin = create(:user, :admin)
      User.where(role: "admin").where.not(id: locked_admin.id).update_all(deactivated_at: Time.current)
      User.where(id: locked_admin.id).update_all(locked: true, locked_until: 99.years.from_now)
      expect(locked_admin.deactivate!).to be(true)
      expect(User.find(locked_admin.id).deactivated_at).to be_present
    end
  end

  describe "no-op syncs the instance" do
    it "deactivate! on a stale instance whose row is already deactivated reports the stored deactivated_at and token_version" do
      stale = User.find(user.id)
      User.where(id: user.id).update_all(["deactivated_at = ?, token_version = token_version + 5", 1.day.ago])
      expect(stale.deactivated_at).to be_nil
      expect(stale.deactivate!).to be(false)
      expect(stale.deactivated_at).to be_present
      expect(stale.token_version).to eq(User.find(user.id).token_version)
      expect(stale).not_to be_changed
    end

    it "reactivate! on a stale instance whose row is already active reports the stored deactivated_at" do
      user.deactivate!
      stale = User.find(user.id)
      User.where(id: user.id).update_all("deactivated_at = NULL, token_version = token_version + 1")
      expect(stale.reactivate!).to be(false)
      expect(stale.deactivated_at).to be_nil
      expect(stale.token_version).to eq(User.find(user.id).token_version)
    end
  end

  describe "#reactivate!" do
    it "is idempotent: returns false and bumps nothing when not deactivated" do
      version = user.token_version
      expect(ApiRefreshToken).not_to receive(:revoke_all_for!)
      expect(user.reactivate!).to be(false)
      expect(User.find(user.id).token_version).to eq(version)
    end

    it "clears deactivated_at, bumps once and does not write active" do
      user.deactivate!
      version = User.find(user.id).token_version
      expect { expect(user.reactivate!).to be(true) }.not_to(change { User.find(user.id).active })
      expect(User.find(user.id)).to have_attributes(deactivated_at: nil, token_version: version + 1)
    end
  end
end
