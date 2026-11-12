# frozen_string_literal: true

require "rails_helper"

# Every way a person is signed in to or out of a space from the staff dashboard
# (add_users, remove_users, sign_out_all_users, import_excel) and the card tap.
RSpec.describe "Signing in and out of a space", type: :request do
  include StaffDashboardSpecHelpers
  include ActiveSupport::Testing::TimeHelpers

  let!(:space) { create(:space) }
  let!(:other_space) { create(:space) }
  let!(:staff) { sign_in_as(:staff, space: space) }
  let(:visitor) { create(:user, :regular_user) }

  describe "add_users" do
    it "signing the same user in twice leaves one active session in the space" do
      2.times { put "/staff_dashboard/add_users", params: { added_users: visitor.username }, as: :json }
      expect(LabSession.where(user: visitor, space: space).active.count).to eq(1)
    end

    it "signs a user in to a second space while still in the first" do
      create(:lab_session, user: visitor, space: other_space, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
      put "/staff_dashboard/add_users", params: { added_users: visitor.username }, as: :json
      expect(LabSession.active_for_user(visitor).pluck(:space_id)).to contain_exactly(space.id, other_space.id)
    end
  end

  describe "remove_users" do
    it "ends only the sessions in the staff member's space" do
      here = sign_in_session(visitor, space)
      elsewhere = sign_in_session(visitor, other_space)
      put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json
      expect(json["signed_out"]).to eq([visitor.username])
      expect(here.reload.sign_out_time).to be <= Time.zone.now
      expect(elsewhere.reload.sign_out_time).to be > Time.zone.now
    end

    it "lists a user who is only in another space as not signed in" do
      elsewhere = sign_in_session(visitor, other_space)
      put "/staff_dashboard/remove_users", params: { dropped_users: [visitor.username] }, as: :json
      expect(json).to include("signed_out" => [], "not_signed_in" => [visitor.username])
      expect(elsewhere.reload.sign_out_time).to be > Time.zone.now
    end
  end

  describe "sign_out_all_users" do
    it "ends every active session in the space and none in another space" do
      first = sign_in_session(visitor, space)
      second = sign_in_session(visitor, space)
      elsewhere = sign_in_session(create(:user, :regular_user), other_space)
      post staff_dashboard_sign_out_all_users_path
      expect(first.reload.sign_out_time).to be <= Time.zone.now
      expect(second.reload.sign_out_time).to be <= Time.zone.now
      expect(elsewhere.reload.sign_out_time).to be > Time.zone.now
    end
  end

  describe "import_excel" do
    let(:sheet) do
      fixture_file_upload(
        Rails.root.join("spec/support/assets", "excel-login.xlsx"),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      )
    end

    it "signs the listed users in for 6 hours" do
      create(:user, :regular_user, username: "Bob1")
      freeze_time do
        post "/staff_dashboard/import_excel", params: { file: sheet }
        row = LabSession.sole
        expect(row.space_id).to eq(space.id)
        expect(row.sign_out_time).to eq(Time.zone.now + 6.hours)
      end
    end

    it "does not add a second session for a user already in the space" do
      bob = create(:user, :regular_user, username: "Bob1")
      sign_in_session(bob, space)
      expect { post "/staff_dashboard/import_excel", params: { file: sheet } }.not_to change(LabSession, :count)
    end
  end
end
