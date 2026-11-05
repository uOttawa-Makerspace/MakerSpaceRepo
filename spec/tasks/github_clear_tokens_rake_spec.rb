# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "github:clear_tokens" do
  let!(:linked) { create(:user, :regular_user).tap { |u| u.update_column(:access_token, "gho_secret") } }
  let!(:other) { create(:user, :regular_user) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("github:clear_tokens")
    Rake::Task["github:clear_tokens"].reenable
  end

  after { ENV.delete("DRY_RUN") }

  it "nulls every stored token and prints the count" do
    expect { Rake::Task["github:clear_tokens"].invoke }.to output(/Cleared the GitHub access token for 1 user/).to_stdout
    expect(linked.reload.access_token).to be_nil
  end

  it "changes nothing with DRY_RUN=1 but reports the count" do
    ENV["DRY_RUN"] = "1"
    expect { Rake::Task["github:clear_tokens"].invoke }.to output(/DRY RUN\] 1 user/).to_stdout
    expect(linked.reload.access_token).to eq("gho_secret")
  end

  it "is idempotent" do
    Rake::Task["github:clear_tokens"].invoke
    Rake::Task["github:clear_tokens"].reenable
    expect { Rake::Task["github:clear_tokens"].invoke }.to output(/for 0 user/).to_stdout
  end
end
