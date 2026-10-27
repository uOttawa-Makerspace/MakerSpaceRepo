require "rails_helper"

RSpec.describe User, "#admin_lock! / #admin_unlock!" do
  let(:user) { create(:user, :regular_user) }

  it "locks for 99 years with MAX_AUTH_ATTEMPTS attempts and bumps token_version" do
    expect { user.admin_lock! }.to change { user.reload.token_version }.by(1)
    expect(user).to have_attributes(locked: true, auth_attempts: User::MAX_AUTH_ATTEMPTS)
    expect(user.locked_until).to be > 90.years.from_now
  end

  it "keeps a concurrent token_version bump (e.g. a password reset between the load and the lock)" do
    stale = User.find(user.id) # loaded at version 0
    User.where(id: user.id).update_all("token_version = token_version + 1") # concurrent reset
    stale.admin_lock!
    expect(stale.token_version).to be > 1 # greater than both the stale copy (0) and the concurrent write (1)
    expect(User.find(user.id).token_version).to eq(2)
  end

  it "does not validate (a legacy-invalid row can still be locked)" do
    user.update_column(:username, "!")
    expect(user.reload).not_to be_valid
    expect { user.admin_lock! }.not_to raise_error
    expect(user.reload.locked).to be(true)
  end

  it "disconnects the user's cable connections when locking, not when unlocking" do
    remote = double(disconnect: nil)
    expect(ActionCable.server.remote_connections).to receive(:where).with(current_user: user).once.and_return(remote)
    user.admin_lock!
    user.admin_unlock!
  end

  it "unlocks without restoring the revoked token_version" do
    user.admin_lock!
    version = user.token_version
    user.admin_unlock!
    expect(user.reload).to have_attributes(locked: false, locked_until: nil, auth_attempts: 0, token_version: version)
  end
end
