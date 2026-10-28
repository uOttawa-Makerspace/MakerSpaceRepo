# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "api:prune_refresh_tokens" do
  let(:user) { create(:user) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("api:prune_refresh_tokens")
    Rake::Task["api:prune_refresh_tokens"].reenable
  end

  def issue(now:, **attrs)
    token = ApiRefreshToken.issue!(user, now: now)
    token.update_columns(attrs) if attrs.any?
    token
  end

  it "deletes rows expired, past the cap, or revoked more than 7 days ago, and keeps the rest" do
    old_expiry = issue(now: 40.days.ago) # expired 10 days ago
    old_cap = issue(now: 100.days.ago, expires_at: 2.days.from_now) # family cap passed 10 days ago
    old_revoked = issue(now: 20.days.ago, revoked_at: 8.days.ago, expires_at: 10.days.from_now)
    recently_expired = issue(now: 36.days.ago) # expired 6 days ago
    recently_revoked = issue(now: 5.days.ago, revoked_at: 6.days.ago)
    live = issue(now: 1.day.ago)

    expect { Rake::Task["api:prune_refresh_tokens"].invoke }.to output(/Pruned 3 /).to_stdout

    expect(ApiRefreshToken.where(id: [old_expiry, old_cap, old_revoked].map(&:id))).to be_empty
    expect(ApiRefreshToken.where(id: [recently_expired, recently_revoked, live].map(&:id)).count).to eq(3)
  end

  it "does not let a row deleted by the prune between lookup and rotation raise" do
    token = issue(now: 40.days.ago)
    found = ApiRefreshToken.find_by_raw(token.raw_token)
    ApiRefreshToken.prune!
    expect(found.rotate!).to be_nil
  end

  it "is scheduled in config/recurring.yml for production" do
    recurring = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
    expect(recurring.dig("production", "prune_api_refresh_tokens", "command")).to eq("ApiRefreshToken.prune!")
  end
end
