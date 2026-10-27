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
      double("remote").tap { |remote| allow(remote).to receive(:disconnect) { disconnected << current_user } }
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

# A failing cable broadcast (solid_cable INSERT) must not undo or mask a committed change.
RSpec.describe "Cable disconnect failures", type: :request do
  let(:password) { "asa32A353#" }
  let(:new_pw) { "Brand-new-pw-7731!" }
  let(:error) { ActiveRecord::StatementInvalid.new("cable db down") }

  before do
    block_external_http!
    allow(ActionCable.server.remote_connections).to receive(:where).and_raise(error)
    allow(Rails.error).to receive(:report).and_call_original
  end

  def login!(user)
    post login_authentication_path, params: { username_email: user.username, password: password }
    user
  end

  it "still completes a password change (notice, own session kept, mail sent) and reports the error" do
    user = login!(create(:user, :regular_user))
    expect do
      patch change_password_user_path(user.username),
            params: { user: { old_password: password, password: new_pw, password_confirmation: new_pw } }
    end.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(flash[:notice]).to match(/Password changed successfully/)
    expect(Rails.error).to have_received(:report).with(error, handled: true)
    expect(user.reload.pword).to eq(new_pw)
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "still completes a password reset and reports the error" do
    user = create(:user, :regular_user)
    expect do
      patch reset_password_confirmation_users_path,
            params: { token: user.generate_token_for(:password_reset), password: new_pw, password_confirmation: new_pw }
    end.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(flash[:alert]).to be_blank
    expect(user.reload.pword).to eq(new_pw)
    expect(Rails.error).to have_received(:report).with(error, handled: true)
  end

  it "reports, and does not raise, when the disconnect call itself fails" do
    remote = double("remote")
    allow(remote).to receive(:disconnect).and_raise(error)
    allow(ActionCable.server.remote_connections).to receive(:where).and_return(remote)
    user = create(:user, :regular_user)
    expect { user.disconnect_cable! }.not_to raise_error
    expect(Rails.error).to have_received(:report).with(error, handled: true)
  end

  it "also swallows and reports non-ActiveRecord broadcast errors (e.g. a Timeout)" do
    timeout = Timeout::Error.new("pool")
    allow(ActionCable.server.remote_connections).to receive(:where).and_raise(timeout)
    expect { create(:user, :regular_user).disconnect_cable! }.not_to raise_error
    expect(Rails.error).to have_received(:report).with(timeout, handled: true)
  end

  it "still stores an admin lock and reports the error" do
    login!(create(:user, :admin))
    target = create(:user, :regular_user)
    put toggle_lock_user_admin_users_path, params: { id: target.id }
    expect(response).not_to have_http_status(:internal_server_error)
    expect(target.reload.locked).to be(true)
    expect(Rails.error).to have_received(:report).with(error, handled: true)
  end
end

RSpec.describe "Cable disconnects on soft delete / deactivation", type: :request do
  let(:password) { "asa32A353#" }
  let(:disconnected) { [] }

  before do
    block_external_http!
    allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
      double("remote").tap { |remote| allow(remote).to receive(:disconnect) { disconnected << current_user } }
    end
  end

  it "disconnects a soft-deleted user (admin delete), not on restore" do
    admin = create(:user, :admin)
    post login_authentication_path, params: { username_email: admin.username, password: password }
    target = create(:user, :regular_user)
    delete delete_user_admin_users_path, params: { id: target.id, password: password }
    expect(User.unscoped.find(target.id).deleted).to be(true)
    expect(disconnected).to eq([target])
    patch restore_user_admin_users_path, params: { id: target.id }
    expect(disconnected).to eq([target])
  end

  it "disconnects on deactivation, not on re-activation" do
    user = create(:user, :regular_user)
    user.update!(active: false)
    expect(disconnected).to eq([user])
    user.update!(active: true)
    expect(disconnected).to eq([user])
  end

  it "disconnects on deleted=true, not on deleted=false" do
    user = create(:user, :regular_user)
    user.update!(deleted: true)
    user.update!(deleted: false)
    expect(disconnected).to eq([user])
  end
end

RSpec.describe "Cable disconnect on hard account deletion", type: :request do
  let(:password) { "asa32A353#" }
  let(:disconnected) { [] }

  before do
    block_external_http!
    allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
      double("remote").tap { |remote| allow(remote).to receive(:disconnect) { disconnected << current_user } }
    end
  end

  it "disconnects when the account is destroyed" do
    user = create(:user, :regular_user)
    user.destroy
    expect(disconnected).to include(user)
  end
end

RSpec.describe User, "role/soft-delete writes" do
  let(:disconnected) { [] }

  before do
    allow(ActionCable.server.remote_connections).to receive(:where) do |current_user:|
      double("remote").tap { |r| allow(r).to receive(:disconnect) { disconnected << current_user } }
    end
  end

  it "rejects an unknown role" do
    expect { create(:user, :staff).change_role!("root") }.to raise_error(ArgumentError)
  end

  it "disconnects a soft delete inside an outer transaction only after the outer commit" do
    user = create(:user, :regular_user)
    User.transaction do
      user.soft_delete!
      expect(disconnected).to be_empty
    end
    expect(disconnected).to eq([user])
  end
end
