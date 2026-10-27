require "rails_helper"
require Rails.root.join("db/migrate/20261026000001_add_token_version_to_users")

# The column already exists in the test schema, so the backfill step is
# exercised on its own (it is what `up` runs right after add_column).
RSpec.describe AddTokenVersionToUsers do
  let(:admin_locked_far) { create(:user, :regular_user) }
  let(:admin_locked_nil) { create(:user, :regular_user) }
  let(:timed) { create(:user, :regular_user) }
  let(:unlocked) { create(:user, :regular_user) }
  let(:lapsed) { create(:user, :regular_user) }
  let(:timed_hours) { create(:user, :regular_user) }
  let(:two_days) { create(:user, :regular_user) }

  before do
    admin_locked_far.update_columns(locked: true, locked_until: 99.years.from_now)
    admin_locked_nil.update_columns(locked: true, locked_until: nil)
    timed.update_columns(locked: true, locked_until: 4.minutes.from_now)
    lapsed.update_columns(locked: true, locked_until: 1.hour.ago)
    timed_hours.update_columns(locked: true, locked_until: 20.hours.from_now)
    two_days.update_columns(locked: true, locked_until: 2.days.from_now)
  end

  def backfill
    ActiveRecord::Migration.suppress_messages { described_class.new.backfill_admin_locked_users }
  end

  it "bumps token_version for admin-locked users (99 years, or no end) and nobody else" do
    unlocked
    backfill
    expect(admin_locked_far.reload.token_version).to eq(1)
    expect(admin_locked_nil.reload.token_version).to eq(1)
    expect(timed.reload.token_version).to eq(0)
    expect(lapsed.reload.token_version).to eq(0)
    expect(timed_hours.reload.token_version).to eq(0) # within the one-day threshold: timed
    expect(two_days.reload.token_version).to eq(1) # beyond it: admin
    expect(unlocked.reload.token_version).to eq(0)
  end

  it "is idempotent" do
    backfill
    expect { backfill }.not_to(change { [admin_locked_far, admin_locked_nil].map { |u| u.reload.token_version } })
  end

  it "leaves the lock fields untouched" do
    expect { backfill }.not_to(change { admin_locked_far.reload.slice(:locked, :locked_until) })
  end

  it "kills the pre-deploy session-less tokens of an admin-locked user but not of a timed-locked one" do
    old_tokens = [admin_locked_far, timed].map { |u| JWT.encode({ user_id: u.id, exp: 1.day.from_now.to_i }, Rails.application.credentials.secret_key_base, "HS256") }
    backfill
    expect(JwtAuthenticator.user_for("Bearer #{old_tokens[0]}")).to be_nil
    expect(JwtAuthenticator.user_for("Bearer #{old_tokens[1]}")).to eq(timed)
  end

  it "up adds the column and down removes it (reversible)" do
    conn = ActiveRecord::Base.connection
    ActiveRecord::Migration.suppress_messages do
      m = described_class.new
      m.down
      expect(conn.column_exists?(:users, :token_version)).to be(false)
      m.up
    end
    User.reset_column_information
    expect(conn.column_exists?(:users, :token_version)).to be(true)
  end
end
