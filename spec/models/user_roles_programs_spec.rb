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

  describe ".text_search" do
    it "does not escape wildcards (legacy staff dashboard behaviour)" do
      u = create(:user, name: "Wild Card")
      expect(User.text_search("%")).to include(u)
      expect(User.text_search(User.sanitize_sql_like("%"))).not_to include(u)
    end
  end
end
