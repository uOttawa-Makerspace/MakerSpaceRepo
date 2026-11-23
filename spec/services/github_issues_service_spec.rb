require "rails_helper"

RSpec.describe GithubIssuesService do
  let(:installation_id) { Rails.application.credentials[:test].github.ceed_issues.installation_id }

  before do
    stub_request(:post, "https://api.github.com/app/installations/#{installation_id}/access_tokens")
      .to_return(status: 201, body: { token: "installation-token" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "bounds the GitHub calls and keeps Octokit's own headers" do
    options = described_class.new.client.connection_options
    expect(options[:request]).to eq(open_timeout: 5, timeout: 20)
    expect(options[:headers]).to eq(Octokit::Default.connection_options[:headers])
  end

  it "gives each client its own connection options" do
    first = described_class.new.client
    second = described_class.new.client
    expect(first.connection_options).not_to be(second.connection_options)
  end
end
