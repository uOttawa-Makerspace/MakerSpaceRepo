# frozen_string_literal: true

require "rails_helper"

# the React app's Help form calls `PUT /send_email` (JSON, Bearer
# token) and sends the mail; it does not update the caller's own name/email.
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
    end.to change { deliveries.size }.by(2)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "sent")
    expect(deliveries.map { |m| [m.to, m.bcc] })
      .to contain_exactly([["original@example.com"], nil], [["uottawa.makerepo@gmail.com"], nil])
    deliveries.each do |mail|
      expect(mail.subject).to eq("Issue Report | Printer will not start")
      expect(mail.body.encoded).to include("It beeps three times", "2.4.1")
    end

    user.reload
    expect(user.name).to eq("Original Name")
    expect(user.email).to eq("original@example.com")
  end

  it "answers success and keeps the request when its job cannot be queued; the sweep sends it later, once" do
    allow(HelpFilingJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
    expect(Rails.error).to receive(:report).with(an_instance_of(ActiveJob::EnqueueError), hash_including(handled: true))
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json") }
    end.to change(Help, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "sent")
    expect(deliveries).to be_empty

    allow(HelpFilingJob).to receive(:perform_later).and_call_original
    travel(Help::RESEND_AFTER + 1.minute) { perform_enqueued_jobs { HelpFilingSweepJob.perform_now } }
    expect(deliveries.map(&:to)).to eq([["uottawa.makerepo@gmail.com"], ["original@example.com"]])
    expect(Help.last.gh_issue_number).to eq("42")
  end

  # the confirmation goes to the account email, never the posted one.
  it "ignores the posted email and name for addressing (no mail relay)" do
    expect do
      perform_enqueued_jobs do
        put "/send_email", params: payload.merge(email: "victim@example.com", name: "Someone Else").to_json,
                           headers: headers.merge("Content-Type" => "application/json")
      end
    end.to change { deliveries.size }.by(2)

    expect(deliveries.map(&:to)).to contain_exactly(["original@example.com"], ["uottawa.makerepo@gmail.com"])
    deliveries.each do |mail|
      expect(mail.body.encoded).to include("Original Name")
      expect(mail.body.encoded).not_to include("Someone Else")
      expect(Array(mail.to) + Array(mail.cc) + Array(mail.bcc)).not_to include("victim@example.com")
    end
  end

  # same persistence path as HelpController#create.
  it "creates the Help record, answers, and its job opens the GitHub issue" do
    expect_any_instance_of(GithubIssuesService).to receive(:create_issue)
      .with(hash_including(reporter: "Original Name", title: "Printer will not start"))
      .and_return({ number: 77 })

    expect do
      put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json")
    end.to change(Help, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(Help.last).to have_attributes(gh_issue_number: nil, user: user, source: "app", app_version: "2.4.1")
    perform_enqueued_jobs
    expect(Help.last.gh_issue_number).to eq("77")
  end

  # GithubIssuesService#create_issue returns `false` on an Octokit error: the request is not told, the job tries again
  it "answers success and sends the mails when the GitHub API call fails; the issue is filed later" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)

    expect do
      perform_enqueued_jobs(only: ApplicationMailDeliveryJob) do
        put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json")
        HelpFilingJob.perform_now(Help.last.id)
      end
    end.to change(Help, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(deliveries.size).to eq(2)
    expect(Help.last.gh_issue_number).to be_nil
    expect(HelpFilingJob).to have_been_enqueued.with(Help.last.id).at_least(:once)
  end

  it "rejects invalid input with 422 JSON errors and sends nothing" do
    expect do
      perform_enqueued_jobs { put "/send_email", params: payload.merge(subject: "short").to_json, headers: headers.merge("Content-Type" => "application/json") }
    end.not_to(change { deliveries.size })

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["errors"].join).to include("Subject")
    expect(user.reload.name).to eq("Original Name")
  end

  it "accepts a long subject, comments and app version as before: stored in full, mailed in full, GitHub text bounded" do
    posted = nil
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { |_s, **kw| posted = kw; { number: 5 } }
    long = payload.merge(subject: "S" * 300, comments: "#{'c' * 6000} end-marker", app_version: "v" * 80)
    perform_enqueued_jobs { put "/send_email", params: long.to_json, headers: headers.merge("Content-Type" => "application/json") }
    expect(response).to have_http_status(:ok)
    expect(Help.last).to have_attributes(subject: "S" * 300, app_version: "v" * 80)
    expect(Help.last.comments.to_plain_text).to end_with("end-marker")
    expect(posted[:title]).to end_with(Help::TRUNCATED_TITLE)
    expect(posted[:body]).not_to end_with(Help::TRUNCATED_BODY) # 6000 characters fit GitHub's body
    deliveries.each { |mail| expect(mail.body.encoded).to include("end-marker", "v" * 80) }
    expect(deliveries.size).to eq(2)
  end

  it "sends a body GitHub would refuse as a bounded issue, with the full text in the mails" do
    posted = nil
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { |_s, **kw| posted = kw; { number: 5 } }
    perform_enqueued_jobs do
      put "/send_email", params: payload.merge(comments: "#{'c' * 70_000} end-marker").to_json,
                         headers: headers.merge("Content-Type" => "application/json")
    end
    expect(response).to have_http_status(:ok)
    expect(posted[:body]).to end_with(Help::TRUNCATED_BODY)
    expect(deliveries.map { |m| m.body.decoded.include?("end-marker") }).to eq([true, true])
  end

  it "sends for an account whose saved name is shorter than a typed name may be" do
    user.update_columns(name: "Q")
    put "/send_email", params: payload.to_json, headers: headers.merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:ok)
    expect(Help.last.name).to eq("Q")
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
      allow(RateLimitCounter).to receive(:increment) { |key, *| counts[key] += 1 }
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
