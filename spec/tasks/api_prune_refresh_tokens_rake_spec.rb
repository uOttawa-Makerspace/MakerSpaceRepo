# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "api:prune_refresh_tokens" do
  include ActiveSupport::Testing::TimeHelpers

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
    old_cap = issue(now: 100.days.ago) # family cap (and so expiry) passed 10 days ago
    old_revoked = issue(now: 20.days.ago, revoked_at: 8.days.ago, expires_at: 10.days.from_now)
    recently_expired = issue(now: 36.days.ago) # expired 6 days ago
    recently_revoked = issue(now: 5.days.ago, revoked_at: 6.days.ago)
    live = issue(now: 1.day.ago)

    expect { Rake::Task["api:prune_refresh_tokens"].invoke }.to output(/Pruned 3 /).to_stdout

    expect(ApiRefreshToken.where(id: [old_expiry, old_cap, old_revoked].map(&:id))).to be_empty
    expect(ApiRefreshToken.where(id: [recently_expired, recently_revoked, live].map(&:id)).count).to eq(3)
  end

  it "keeps a rotated token past 7 days so a replay of it is still detected as theft" do
    first = issue(now: Time.current)
    successor = first.rotate!
    travel_to(8.days.from_now) do
      ApiRefreshToken.prune!
      expect(ApiRefreshToken.exists?(first.id)).to be(true)
      expect(ApiRefreshToken.find_by_raw(first.raw_token).rotate!).to be_nil
      expect(successor.reload.revoked_at).to be_present
    end
  end

  it "prunes rotated tokens only once the family cap plus 7 days has passed" do
    first = issue(now: 100.days.ago) # cap passed 10 days ago
    first.update_columns(revoked_at: 50.days.ago, replaced_by_id: 1)
    young = issue(now: 20.days.ago)
    young.update_columns(revoked_at: 15.days.ago, replaced_by_id: 1) # family cap still 70 days away
    ApiRefreshToken.prune!
    expect(ApiRefreshToken.exists?(first.id)).to be(false)
    expect(ApiRefreshToken.exists?(young.id)).to be(true)
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
