require "rails_helper"

RSpec.describe GithubIssuesService do
  it "bounds the GitHub calls and keeps Octokit's own headers" do
    expect(described_class::CONNECTION_OPTIONS[:request]).to eq(open_timeout: 5, timeout: 20)
    expect(described_class::CONNECTION_OPTIONS[:headers]).to eq(Octokit::Default.connection_options[:headers])
  end
end
