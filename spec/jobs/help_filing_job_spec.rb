# frozen_string_literal: true

require "rails_helper"

RSpec.describe HelpFilingJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, :regular_user, name: "Account Owner", email: "owner@example.com") }

  def deliveries = ActionMailer::Base.deliveries

  def help_request(**attrs)
    Help.create!({ name: "Pat Visitor", email: "pat@example.test", subject: "Booking does not work",
                   comments: "I cannot book the room", source: Help::APP }.merge(attrs))
  end

  before do
    block_external_http!
    deliveries.clear
  end

  it "mails the team and opens the GitHub issue for a guest's request, and records both" do
    help = help_request
    freeze_time do
      perform_enqueued_jobs { described_class.perform_later(help.id) }
      expect(help.reload).to have_attributes(gh_issue_number: "111", filed_at: Time.current, mailed_at: Time.current)
    end
    expect(deliveries.map(&:to)).to eq([["uottawa.makerepo@gmail.com"]])
    expect(deliveries.first.reply_to).to eq(["pat@example.test"])
    expect(deliveries.first.body.encoded).to include("submitted through the MakerRepo app")
    expect(help).to be_finished
  end

  it "sends a signed-in user's request to the team first and to the account address" do
    help = help_request(user: user, name: user.name, email: user.email)
    perform_enqueued_jobs { described_class.perform_now(help.id) }
    expect(deliveries.map(&:to)).to eq([["uottawa.makerepo@gmail.com"], ["owner@example.com"]])
  end

  it "words a guest's web form request as coming from the help page" do
    help = help_request(source: Help::HELP_PAGE)
    perform_enqueued_jobs { described_class.perform_now(help.id) }
    expect(deliveries.last.body.encoded).to include("submitted through the MakerRepo help page")
  end

  it "does nothing on a second run: one issue, one set of mails" do
    service = GithubIssuesService.new
    allow(GithubIssuesService).to receive(:new).and_return(service)
    allow(service).to receive(:create_issue).and_return({ number: 42 })
    help = help_request(user: user, name: user.name, email: user.email)

    perform_enqueued_jobs do
      described_class.perform_now(help.id)
      described_class.perform_now(help.id)
    end

    expect(service).to have_received(:create_issue).once
    expect(deliveries.size).to eq(2)
    expect(help.reload.gh_issue_number).to eq("42")
  end

  it "does nothing for a request that no longer exists" do
    expect { described_class.perform_now(0) }.not_to raise_error
    expect(deliveries).to be_empty
  end

  it "mails once and runs again later when GitHub opens no issue, then files it" do
    answers = [false, { number: 7 }]
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { answers.shift }
    help = help_request

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { described_class.perform_now(help.id) }
    expect(help.reload).to have_attributes(gh_issue_number: nil, filed_at: nil)
    expect(help.mailed_at).to be_present
    expect(described_class).to have_been_enqueued.with(help.id)

    perform_enqueued_jobs
    expect(help.reload).to have_attributes(gh_issue_number: "7")
    expect(help.filed_at).to be_present
    expect(deliveries.size).to eq(1)
  end

  it "runs again when GitHub cannot be reached" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_raise(Faraday::ConnectionFailed, "down")
    help = help_request
    described_class.perform_now(help.id)
    expect(described_class).to have_been_enqueued.with(help.id)
    expect(help.reload.filed_at).to be_nil
  end

  it "reports the failure after the last attempt and leaves the row for the sweep" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
    help = help_request
    expect(Rails.error).to receive(:report)
      .with(an_instance_of(described_class::IssueNotFiled), hash_including(handled: true, context: hash_including(help_id: help.id)))

    perform_enqueued_jobs { described_class.perform_later(help.id) }

    expect(help.reload.filed_at).to be_nil
    expect(Help.unfinished).to include(help)
    expect(deliveries.size).to eq(1)
  end

  it "queues neither mail and records nothing when the mails cannot be queued, and sends both on the next run" do
    help = help_request(user: user, name: user.name, email: user.email)
    allow(ActionMailer).to receive(:deliver_all_later).and_raise(ActiveRecord::ConnectionNotEstablished, "queue down")
    expect { described_class.perform_now(help.id) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    expect(help.reload).to have_attributes(mailed_at: nil, filed_at: nil)

    allow(ActionMailer).to receive(:deliver_all_later).and_call_original
    perform_enqueued_jobs { described_class.perform_now(help.id) }
    expect(deliveries.map(&:to)).to eq([["uottawa.makerepo@gmail.com"], ["owner@example.com"]])
    expect(help.reload).to be_finished
  end

  # The service answers with a fixed issue in test; here it goes through Octokit to a stubbed GitHub API, as in
  # production.
  context "when the issue is opened through the GitHub API" do
    let(:installation_id) { Rails.application.credentials[:test].github.ceed_issues.installation_id }
    let!(:token_call) do
      stub_request(:post, "https://api.github.com/app/installations/#{installation_id}/access_tokens")
        .to_return(status: 201, body: { token: "installation-token" }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end
    let!(:issue_call) do
      stub_request(:post, "https://api.github.com/repos/uOttawa-Makerspace/CEED-Issues/issues")
        .to_return(status: 201, body: { number: 7 }.to_json, headers: { "Content-Type" => "application/json" })
    end

    before { allow(Rails.env).to receive(:test?).and_return(false) }

    it "mails the copies, opens the issue once and records both" do
      help = help_request(subject: "Réservation échouée 🙂 @team #12", comments: "Ça ne marche pas: <b>GH-3</b>")
      perform_enqueued_jobs { described_class.perform_now(help.id) }

      expect(help.reload).to have_attributes(gh_issue_number: "7")
      expect(help).to be_finished
      expect(deliveries.size).to eq(1)
      expect(token_call).to have_been_made.once
      expect(issue_call.with { |req| JSON.parse(req.body)["title"].start_with?("Réservation échouée 🙂 @‍") })
        .to have_been_made.once
    end

    it "files each waiting request once from the sweep" do
      helps = travel_to(1.hour.ago) { [help_request, help_request(user: user, name: user.name, email: user.email)] }
      perform_enqueued_jobs do
        HelpFilingSweepJob.perform_now
        HelpFilingSweepJob.perform_now
      end

      expect(helps.map(&:reload)).to all(be_finished)
      expect(issue_call).to have_been_made.twice
      expect(deliveries.size).to eq(3)
    end
  end
end
