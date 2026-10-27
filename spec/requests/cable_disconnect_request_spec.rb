require "rails_helper"

# A10: a user's open websocket connections are closed when the credentials or
# rights behind them change (the handshake re-checks everything on reconnect).
RSpec.describe "Cable disconnects", type: :request do
  let(:password) { "asa32A353#" }
  let(:new_pw) { "Brand-new-pw-7731!" }
  let(:disconnected) { [] }

  before do
    block_external_http!
    allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
      double("remote", disconnect: disconnected << current_user)
    end
  end

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
    user
  end

  it "disconnects on logout, and does nothing for a guest logout" do
    get logout_path
    expect(disconnected).to be_empty
    user = login!(create(:user, :regular_user))
    get logout_path
    expect(disconnected).to eq([user])
  end

  it "disconnects on a password change" do
    user = login!(create(:user, :regular_user))
    patch change_password_user_path(user.username),
          params: { user: { old_password: password, password: new_pw, password_confirmation: new_pw } }
    expect(disconnected).to include(user)
  end

  it "disconnects on a password reset" do
    user = create(:user, :regular_user)
    patch reset_password_confirmation_users_path,
          params: { token: user.generate_token_for(:password_reset), password: new_pw, password_confirmation: new_pw }
    expect(disconnected).to include(user)
  end

  describe "role changes (PATCH /admin/users/set_role)" do
    before { login!(create(:user, :admin)) }

    def set_role(user, role) = patch(set_role_admin_users_path, params: { role: role, user_ids: [user.id] })

    it "disconnects a demoted staff member or admin" do
      staff = create(:user, :staff)
      other_admin = create(:user, :admin)
      set_role(staff, "regular_user")
      set_role(other_admin, "regular_user")
      expect(disconnected).to match_array([staff, other_admin])
    end

    it "does not disconnect on promotion or a staff-to-admin change" do
      set_role(create(:user, :regular_user), "staff")
      set_role(create(:user, :staff), "admin")
      expect(disconnected).to be_empty
    end
  end

  it "disconnects an admin-locked user, not on unlock" do
    login!(create(:user, :admin))
    target = create(:user, :regular_user)
    put toggle_lock_user_admin_users_path, params: { id: target.id }
    expect(disconnected).to eq([target])
    put toggle_lock_user_admin_users_path, params: { id: target.id }
    expect(disconnected).to eq([target])
  end
end
