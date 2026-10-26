# frozen_string_literal: true

require "rails_helper"

# FIXED(D-API01): the React app's Help form calls `PUT /send_email` (JSON, Bearer
# token). It used to fall through to `PUT /:username` -> users#update and overwrite
# the caller's own name/email without sending any mail.
RSpec.describe "PUT /send_email (React Help form)", type: :request do
  let(:user) { create(:user, :regular_user, name: "Original Name", email: "original@example.com") }
  let(:headers) { { "Authorization" => "Bearer #{user.token}" } }
  let(:payload) do
    {
      name: "Help Seeker",
      email: "seeker@example.com",
      subject: "Printer will not start",
      comments: "It beeps three times and stops.",
      app_version: "2.4.1"
    }
  end

  before do
    block_external_http!
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: 42 })
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  it "sends the support email and never touches the signed-in user" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json", "Accept" => "application/json") }
    end.to change { deliveries.size }.by(1)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "sent")
    mail = deliveries.last
    expect(mail.to).to eq(["original@example.com"])
    expect(mail.bcc).to include("uottawa.makerepo@gmail.com")
    expect(mail.subject).to eq("Issue Report | Printer will not start")
    expect(mail.body.encoded).to include("It beeps three times", "2.4.1")

    user.reload
    expect(user.name).to eq("Original Name")
    expect(user.email).to eq("original@example.com")
  end

  # FIXED(D-API01/D-NEW-A13-3): the confirmation goes to the account email, never the posted one.
  it "ignores the posted email and name for addressing (no mail relay)" do
    expect do
      perform_enqueued_jobs do
        put "/send_email", params: payload.merge(email: "victim@example.com", name: "Someone Else").to_json,
                           headers: headers.merge("Content-Type" => "application/json")
      end
    end.to change { deliveries.size }.by(1)

    mail = deliveries.last
    expect(mail.to).to eq(["original@example.com"])
    expect(mail.body.encoded).to include("Original Name")
    expect(mail.body.encoded).not_to include("Someone Else")
    expect(mail.to + (mail.cc || [])).not_to include("victim@example.com")
  end

  # FIXED(D-API01/D-NEW-A13-3): same persistence path as HelpController#create.
  it "creates the Help record and attempts the GitHub issue" do
    expect_any_instance_of(GithubIssuesService).to receive(:create_issue)
      .with(hash_including(reporter: "Original Name", title: "Printer will not start"))
      .and_return({ number: 77 })

    expect do
      put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json")
    end.to change(Help, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(Help.last.gh_issue_number).to eq("77")
  end

  # FIXED(D-API01): GithubIssuesService#create_issue returns `false` on an Octokit error
  it "returns 422 JSON errors and sends no email when the GitHub API call fails (create_issue => false)" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)

    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json") }
    end.not_to(change { [deliveries.size, Help.count] })

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"].join).to include("Internal error")
  end

  it "rejects invalid input with 422 JSON errors and sends nothing" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.merge(subject: "short").to_json, headers: headers.merge("Content-Type" => "application/json") }
    end.not_to(change { deliveries.size })

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"].join).to include("Subject")
    expect(user.reload.name).to eq("Original Name")
  end

  it "refuses anonymous callers with 401 and sends nothing" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: { "Content-Type" => "application/json" } }
    end.not_to(change { deliveries.size })
    expect(response).to have_http_status(:unauthorized)
  end

  # test env uses :null_store (never counts), so back the limiter's store with a counter
  describe "rate limit" do
    let(:counts) { Hash.new(0) }

    before do
      allow(HelpController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
    end

    def send!(as_headers = headers)
      put "/send_email", params: payload.to_json, headers: as_headers.merge("Content-Type" => "application/json")
    end

    it "allows 5 calls an hour per user, then answers 429 JSON and creates nothing" do
      5.times { send!; expect(response).to have_http_status(:ok) }
      expect { send! }.not_to change(Help, :count)
      expect(response).to have_http_status(:too_many_requests)
      expect(JSON.parse(response.body)).to eq("error" => "Too many requests")
    end

    it "counts per user, not globally" do
      5.times { send! }
      other = create(:user, :regular_user)
      # fresh session: the first user's cookie would otherwise win over the bearer token
      other_session = open_session
      other_session.put "/send_email", params: payload.to_json,
                                       headers: { "Authorization" => "Bearer #{other.token}", "Content-Type" => "application/json" }
      expect(other_session.response).to have_http_status(:ok)
    end
  end

  describe "regression: PUT /:username still updates the real profile" do
    it "updates the profile for the owner" do
      put user_path(user.username),
          params: { user: { name: "Renamed Person" } }.to_json,
          headers: headers.merge("Content-Type" => "application/json")
      expect(user.reload.name).to eq("Renamed Person")
    end
  end
end
