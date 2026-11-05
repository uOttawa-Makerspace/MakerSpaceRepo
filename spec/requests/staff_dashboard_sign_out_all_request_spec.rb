# frozen_string_literal: true

require "rails_helper"

# sign_out_all_users was a state-changing GET (reachable by a
# crafted link); it is POST only. Neither frontend app calls it (inventory).
RSpec.describe "Staff dashboard sign_out_all_users", type: :request do
  let!(:space) { create(:space) }
  let!(:visitor) { create(:user, :regular_user) }
  let!(:session_row) do
    create(:lab_session, space: space, user: visitor, sign_in_time: 1.hour.ago, sign_out_time: 2.hours.from_now)
  end

  it "signs everyone out of the staff member's space on POST" do
    sign_in_as(:staff, space: space)
    post staff_dashboard_sign_out_all_users_path
    expect(response).to redirect_to(staff_dashboard_index_path(space_id: space.id))
    expect(session_row.reload.sign_out_time).to be <= Time.current
  end

  it "does nothing on a plain GET" do
    sign_in_as(:staff, space: space)
    expect { get "/staff_dashboard/sign_out_all_users" }.not_to(change { session_row.reload.sign_out_time })
    expect(session_row.reload.sign_out_time).to be > Time.current
  end

  it "does not sign anyone out for a guest or a regular user" do
    post staff_dashboard_sign_out_all_users_path
    sign_in_as(:regular, space: space)
    post staff_dashboard_sign_out_all_users_path
    expect(session_row.reload.sign_out_time).to be > Time.current
  end
end
