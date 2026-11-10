# frozen_string_literal: true

require "rails_helper"

# Shared by the legacy controllers and /api/v1/users.
RSpec.describe User do
  describe ".change_roles!" do
    it "changes all roles in one go and is all-or-nothing on the last-admin guard" do
      only_admin = create(:user, :admin)
      other = create(:user)
      expect { User.change_roles!([only_admin.id, other.id], "staff") }.to raise_error(User::LastAdminError)
      expect(only_admin.reload.role).to eq("admin")
      expect(other.reload.role).to eq("regular_user")
    end

    it "allows promoting to admin and demoting when another usable admin remains" do
      a = create(:user, :admin)
      create(:user, :admin)
      User.change_roles!([a.id], "regular_user")
      expect(a.reload.role).to eq("regular_user")
    end

    it "rejects an unknown role" do
      u = create(:user)
      expect { User.change_roles!([u.id], "root") }.to raise_error(ArgumentError)
    end
  end

  describe "#sync_programs!" do
    let(:user) { create(:user) }

    it "joins, leaves and keeps (nil) memberships" do
      user.programs.create!(program_type: Program::TEAMS)
      expect(user.sync_programs!(development: true, volunteer: true)).to match_array([Program::DEV_PROGRAM, Program::VOLUNTEER, Program::TEAMS])
      expect(user.sync_programs!(development: false, volunteer: true, teams: false)).to eq([Program::VOLUNTEER])
    end
  end

  describe ".promote_to_staff!" do
    it "promotes a regular user and leaves staff and admin roles alone" do
      regular = create(:user, :regular_user)
      admin = create(:user, :admin)
      staff = create(:user, :staff)
      User.promote_to_staff!([regular.id, admin.id, staff.id])
      expect([regular, admin, staff].map { |u| u.reload.role }).to eq(%w[staff admin staff])
    end

    it "promotes a user whose role is empty" do
      blank = create(:user, :regular_user)
      User.where(id: blank.id).update_all(role: nil)
      User.promote_to_staff!([blank.id])
      expect(blank.reload.role).to eq("staff")
    end

    it "leaves a user who became admin since they were loaded as an admin" do
      stale = create(:user, :regular_user)
      User.where(id: stale.id).update_all(role: "admin")
      expect { User.promote_to_staff!([stale.id]) }.not_to raise_error
      expect(stale.reload.role).to eq("admin")
    end
  end

  describe ".delete_account! actor check" do
    it "refuses when the actor was demoted after the actor was loaded" do
      actor = create(:user, :admin)
      create(:user, :admin)
      target = create(:user, :regular_user)
      stale_actor = User.find(actor.id)
      actor.update_column(:role, "regular_user")

      expect { User.delete_account!(target, actor: stale_actor) }.to raise_error(User::NotAdminError)
      expect(target.reload.deleted).to be(false)
    end

    it "refuses when there is no actor" do
      create(:user, :admin)
      target = create(:user, :regular_user)

      expect { User.delete_account!(target, actor: nil) }.to raise_error(User::NotAdminError)
      expect(target.reload.deleted).to be(false)
    end

    it "deletes when the actor is still an admin" do
      actor = create(:user, :admin)
      target = create(:user, :regular_user)

      expect(User.delete_account!(target, actor: actor)).to be(true)
    end
  end

  describe "#sync_programs! atomicity" do
    it "rolls back the earlier changes when a later one fails" do
      user = create(:user)
      user.programs.create!(program_type: Program::VOLUNTEER)
      allow_any_instance_of(Program).to receive(:destroy).and_raise(ActiveRecord::StatementInvalid, "boom")
      # development is joined first, then leaving volunteer raises
      expect { user.sync_programs!(development: true, volunteer: false) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(user.programs.reload.pluck(:program_type)).to eq([Program::VOLUNTEER])
    end
  end

  describe "#sync_programs! failures that do not raise by themselves" do
    it "rolls back a join when the following leave is refused (destroy returns false)" do
      user = create(:user)
      user.programs.create!(program_type: Program::VOLUNTEER)
      allow_any_instance_of(Program).to receive(:destroy).and_return(false)
      expect { user.sync_programs!(development: true, volunteer: false) }.to raise_error(ActiveRecord::RecordNotDestroyed)
      expect(user.programs.reload.pluck(:program_type)).to eq([Program::VOLUNTEER])
    end

    it "rolls back an earlier leave when a later join is invalid" do
      user = create(:user)
      user.programs.create!(program_type: Program::DEV_PROGRAM)
      allow_any_instance_of(Program).to receive(:valid?).and_return(false)
      expect { user.sync_programs!(development: false, volunteer: true) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(user.programs.reload.pluck(:program_type)).to eq([Program::DEV_PROGRAM])
    end
  end

  describe ".text_search" do
    it "matches wildcard characters in the query literally" do
      u = create(:user, name: "Wild Card")
      pct = create(:user, name: "100% Real")
      expect(User.text_search("%")).to contain_exactly(pct)
      expect(User.text_search("_")).not_to include(u)
    end
  end
end
