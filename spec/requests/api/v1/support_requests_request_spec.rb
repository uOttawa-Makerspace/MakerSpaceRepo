# frozen_string_literal: true

require "rails_helper"

# Contract: doc/api/v1/support_requests.md
RSpec.describe "POST /api/v1/support_requests", type: :request do
  let(:json_headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" } }
  let(:user) { create(:user, :regular_user, name: "Account Owner", email: "owner@example.com") }
  let(:payload) do
    { name: "Help Seeker", email: "seeker@example.com", subject: "Printer will not start",
      comments: "It beeps three times and stops.", app_version: "2.4.1" }
  end

  def body = response.parsed_body
  def fields = body.dig("error", "fields")
  def auth(u) = { "Authorization" => "Bearer #{ApiAccessToken.issue(u).first}" }
  def deliveries = ActionMailer::Base.deliveries

  def post_request(data = payload, as: nil, ip: nil)
    env = json_headers.merge(as ? auth(as) : {})
    env["REMOTE_ADDR"] = ip if ip
    post "/api/v1/support_requests", params: data.to_json, headers: env
  end

  before do
    block_external_http!
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: 42 })
  end

  after { Help.find_each(&:destroy) }

  it "accepts an anonymous request: 202, a Help row, and one mail to the team only" do
    expect do
      perform_enqueued_jobs { post_request }
    end.to change(Help, :count).by(1).and change { deliveries.size }.by(1)

    expect(response).to have_http_status(:accepted)
    expect(body).to eq("status" => "accepted")
    expect(response.body).not_to include("beeps")
    expect(Help.last.gh_issue_number).to eq("42")

    mail = deliveries.last
    expect(mail.to).to eq(["uottawa.makerepo@gmail.com"])
    expect(mail.cc).to be_blank
    expect(mail.bcc).to be_blank
    expect(mail.reply_to).to eq(["seeker@example.com"])
    expect(mail.subject).to eq("Issue Report | Printer will not start")
    expect(mail.body.encoded).to include("Help Seeker", "seeker@example.com", "Printer will not start", "It beeps three times", "App Version: 2.4.1")
  end

  it "never puts an anonymous caller's address in To/Cc/Bcc (no mail relay)" do
    perform_enqueued_jobs { post_request(payload.merge(email: "victim@example.org")) }
    expect(deliveries.size).to eq(1)
    mail = deliveries.last
    expect([mail.to, mail.cc, mail.bcc].flatten.compact).to eq(["uottawa.makerepo@gmail.com"])
    expect(mail.reply_to).to eq(["victim@example.org"])
  end

  it "defangs mentions, cross-references and HTML in the public GitHub issue (anonymous)" do
    posted = nil
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) do |_svc, **kw|
      posted = kw
      { number: 9 }
    end
    post_request(payload.merge(name: "Hi @org/team", subject: "See @someone and #123 now",
                               comments: "ping @someone, fixes #123, GH-5 1 < 2 > 0 a&b"))
    expect(response).to have_http_status(:accepted)
    zwj = "\u200D"
    expect(posted[:reporter]).to eq("Hi @#{zwj}org/team")
    expect(posted[:title]).to eq("See @#{zwj}someone and ##{zwj}123 now")
    expect(posted[:body]).to eq("ping @#{zwj}someone, fixes ##{zwj}123, GH-#{zwj}5 1 &lt; 2 &gt; 0 a&amp;b")
    expect([posted[:reporter], posted[:title], posted[:body]].join).not_to match(/@\w|#\d|GH-\d|</)
  end

  it "opens the GitHub issue exactly as the legacy path does" do
    expect_any_instance_of(GithubIssuesService).to receive(:create_issue)
      .with(hash_including(reporter: "Help Seeker", title: "Printer will not start")).and_return({ number: 7 })
    post_request
    expect(response).to have_http_status(:accepted)
  end

  it "uses the account name and email when signed in, never the posted ones" do
    expect do
      perform_enqueued_jobs { post_request(payload.merge(email: "victim@example.com", name: "Someone Else"), as: user) }
    end.to change { deliveries.size }.by(1)
    expect(response).to have_http_status(:accepted)
    mail = deliveries.last
    expect(mail.to).to eq(["owner@example.com"])
    expect(mail.body.encoded).to include("Account Owner")
    expect(mail.body.encoded).not_to include("Someone Else")
    expect(user.reload).to have_attributes(name: "Account Owner", email: "owner@example.com")
  end

  it "needs no name or email from a signed-in caller" do
    post_request(payload.except(:name, :email), as: user)
    expect(response).to have_http_status(:accepted)
  end

  it "ignores unknown fields (no mass assignment) and a missing app_version" do
    perform_enqueued_jobs { post_request(payload.except(:app_version).merge(gh_issue_number: "999", share_email: true, role: "admin")) }
    expect(response).to have_http_status(:accepted)
    expect(Help.last.gh_issue_number).to eq("42")
    expect(deliveries.last.body.encoded).not_to include("App Version")
  end

  it "ignores a bad Bearer token (public endpoint)" do
    post "/api/v1/support_requests", params: payload.to_json, headers: json_headers.merge("Authorization" => "Bearer junk")
    expect(response).to have_http_status(:accepted)
  end

  describe "422" do
    def expect_rejected(data, *keys)
      expect do
        perform_enqueued_jobs { post_request(data) }
      end.not_to(change { [Help.count, deliveries.size] })
      expect(response).to have_http_status(:unprocessable_content)
      expect(body["error"]["code"]).to eq("validation_failed")
      expect(fields.keys).to include(*keys)
    end

    it "requires every field" do
      expect_rejected({}, "name", "email", "subject", "comments")
    end

    it "rejects a bad email, short name and short subject" do
      expect_rejected(payload.merge(email: "not-an-email"), "email")
      expect_rejected(payload.merge(name: "A"), "name")
      expect_rejected(payload.merge(subject: "too short"), "subject")
    end

    it "caps lengths" do
      expect_rejected(payload.merge(subject: "s" * 201), "subject")
      expect_rejected(payload.merge(comments: "c" * 5001), "comments")
      expect_rejected(payload.merge(app_version: "v" * 51), "app_version")
      expect_rejected(payload.merge(name: "n" * 201), "name")
      post_request(payload.merge(subject: "s" * 200, comments: "c" * 5000))
      expect(response).to have_http_status(:accepted)
    end

    it "treats non-string values as missing" do
      expect_rejected(payload.merge(subject: { a: 1 }, comments: ["x"]), "subject", "comments")
    end

    it "answers a 400 for malformed JSON" do
      post "/api/v1/support_requests", params: "{oops", headers: json_headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  it "answers 503, saves nothing and sends nothing when the GitHub issue cannot be opened" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
    expect do
      perform_enqueued_jobs { post_request }
    end.not_to(change { [Help.count, deliveries.size] })
    expect(response).to have_http_status(:service_unavailable)
    expect(body["error"]["code"]).to eq("service_unavailable")
  end

  # test env uses :null_store (never counts), so back the limiter with a counter
  describe "rate limit" do
    let(:counts) { Hash.new(0) }

    before do
      allow(Api::V1::SupportRequestsController.cache_store).to receive(:increment) { |key, *| counts[key] += 1 }
    end

    it "allows 5 a minute per IP, then 429 with nothing created" do
      5.times { post_request(ip: "10.0.0.1"); expect(response).to have_http_status(:accepted) }
      expect { post_request(ip: "10.0.0.1") }.not_to change(Help, :count)
      expect(response).to have_http_status(:too_many_requests)
      expect(body.dig("error", "code")).to eq("rate_limited")
      post_request(ip: "10.0.0.2")
      expect(response).to have_http_status(:accepted)
    end

    it "limits per user across IPs" do
      5.times { |i| post_request(as: user, ip: "10.0.1.#{i}"); expect(response).to have_http_status(:accepted) }
      post_request(as: user, ip: "10.0.1.99")
      expect(response).to have_http_status(:too_many_requests)
      other = create(:user, :regular_user)
      post_request(as: other, ip: "10.0.1.98")
      expect(response).to have_http_status(:accepted)
    end

    it "limits 20 an hour per IP" do
      allow(Api::V1::SupportRequestsController.cache_store).to receive(:increment) do |key, *|
        counts[key] += 1
        key.include?("ip-minute") || key.include?("user-minute") ? 1 : counts[key]
      end
      20.times { post_request(ip: "10.0.2.1"); expect(response).to have_http_status(:accepted) }
      post_request(ip: "10.0.2.1")
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "CORS" do
    it "answers the React app origin without credentials" do
      post "/api/v1/support_requests", params: payload.to_json, headers: json_headers.merge("Origin" => "https://app.makerepo.com")
      expect(response.headers["Access-Control-Allow-Origin"]).to eq("https://app.makerepo.com")
      expect(response.headers).not_to have_key("Access-Control-Allow-Credentials")
    end
  end
end
