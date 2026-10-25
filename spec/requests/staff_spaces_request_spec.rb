# frozen_string_literal: true

require "rails_helper"

# StaffSpacesController#bulk_add_users (StaffAreaController: staff or admin).
# Guests go to /login?back_to=…; regular users to root with an alert.

RSpec.describe "StaffSpaces", type: :request do
  include SpacesSpecHelpers

  let!(:space_a) { create(:space) }
  let!(:space_b) { create(:space) }
  let!(:target) { create(:user, :regular_user) }
  let(:params) { { space_ids: [space_a.id, space_b.id], user_ids: [target.username] } }

  def state = [StaffSpace.count, target.reload.role]

  describe "auth" do
    it "sends a guest to login with back_to" do
      expect { post bulk_add_users_staff_spaces_path, params: params }.not_to change { state }
      expect(response).to redirect_to(login_path(back_to: bulk_add_users_staff_spaces_path))
    end

    it "sends a regular user to root with an alert (no privilege escalation)" do
      sign_in_as(:regular)
      expect { post bulk_add_users_staff_spaces_path, params: params }.not_to change { state }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You cannot access this area.")
    end
  end

  %i[staff admin].each do |role|
    context "as #{role}" do
      before { sign_in_as(role) }

      it "promotes the users to staff and gives each a StaffSpace per space with distinct palette colours" do
        expect { post bulk_add_users_staff_spaces_path, params: params }.to change(StaffSpace, :count).by(2)
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Successfully added users to spaces.")
        expect(target.reload.role).to eq("staff")
        expect(StaffSpace.where(user: target).pluck(:space_id)).to match_array([space_a.id, space_b.id])
        expect(StaffSpace.where(user: target).pluck(:color)).to all(eq("#e6194b")) # first free colour per space
      end

      it "is idempotent and skips unknown usernames" do
        post bulk_add_users_staff_spaces_path, params: params.merge(user_ids: [target.username, "nobody"])
        expect { post bulk_add_users_staff_spaces_path, params: params }.not_to change(StaffSpace, :count)
        expect(StaffSpace.count).to eq(2)
      end

      it "does not demote an admin target" do
        other = create(:user, :admin)
        post bulk_add_users_staff_spaces_path, params: { space_ids: [space_a.id], user_ids: [other.username] }
        expect(other.reload.role).to eq("admin") # staff? is true for admins, so the role update is skipped
      end

      it "alerts when spaces or users are missing" do
        post bulk_add_users_staff_spaces_path, params: { space_ids: [space_a.id] }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Make sure you selected spaces and users.")
        post bulk_add_users_staff_spaces_path, params: { user_ids: [target.username] }
        expect(flash[:alert]).to eq("Make sure you selected spaces and users.")
        expect(StaffSpace.count).to eq(0)
      end

      it "redirects back to the referer" do
        post bulk_add_users_staff_spaces_path, params: params, headers: { "HTTP_REFERER" => admin_spaces_url }
        expect(response).to redirect_to(admin_spaces_url)
      end
    end
  end

  # WART(D-SP12): a staff user (not just admin) may promote anyone to staff and attach them to any space.
  it "lets a plain staff user create staff accounts from regular users" do
    sign_in_as(:staff)
    post bulk_add_users_staff_spaces_path, params: params
    expect(target.reload.role).to eq("staff")
  end
end
