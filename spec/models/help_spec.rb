require "rails_helper"

RSpec.describe Help, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def valid_attrs(**over)
    { name: "Pat", email: "pat@example.test", subject: "A long enough subject", comments: "Something broke",
      source: Help::APP }.merge(over)
  end

  it "is valid with name, email, subject (10+ chars) and comments" do
    expect(Help.new(valid_attrs)).to be_valid
  end

  it "validates name length, email format, subject length and comments presence" do
    expect(Help.new(valid_attrs(name: "P"))).not_to be_valid
    expect(Help.new(valid_attrs(email: "nope"))).not_to be_valid
    expect(Help.new(valid_attrs(subject: "short"))).not_to be_valid
    expect(Help.new(valid_attrs(comments: ""))).not_to be_valid
    expect(Help.new(valid_attrs(source: nil))).not_to be_valid
    expect(Help.new(valid_attrs(source: Help::HELP_PAGE))).to be_valid
  end

  it "keeps who sent it, from where and the subject" do
    user = create(:user, :regular_user)
    help = Help.create!(valid_attrs(user: user, share_email: "1", app_version: "2.4.1"))
    expect(Help.find(help.id)).to have_attributes(user: user, name: "Pat", email: "pat@example.test", share_email: true,
                                                  subject: "A long enough subject", app_version: "2.4.1", source: "app",
                                                  filed_at: nil, mailed_at: nil, resends: 0)
  end

  it "saves without calling GitHub" do
    expect_any_instance_of(GithubIssuesService).not_to receive(:create_issue)
    help = Help.create!(valid_attrs)
    expect(help.gh_issue_number).to be_nil
  end

  it "opens a GitHub issue on file_issue and stores the issue number and when (stubbed in test)" do
    help = Help.create!(valid_attrs)
    freeze_time do
      expect(help.file_issue).to be(true)
      expect(help.reload).to have_attributes(gh_issue_number: "111", filed_at: Time.current)
    end
  end

  it "opens the issue once: a second file_issue does not call GitHub" do
    help = Help.create!(valid_attrs)
    help.file_issue
    expect_any_instance_of(GithubIssuesService).not_to receive(:create_issue)
    expect(Help.find(help.id).file_issue).to be(true)
  end

  it "keeps the saved report unfiled when no issue number comes back" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: nil })
    help = Help.create!(valid_attrs)
    expect(help.file_issue).to be(false)
    expect(help.reload).to have_attributes(gh_issue_number: nil, filed_at: nil)
    expect(Help.unfinished).to include(help)
  end

  it "treats a failed GitHub call (false) as no issue" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
    expect(Help.create!(valid_attrs).file_issue).to be(false)
  end

  describe ".defang" do
    it "leaves plain text unchanged" do
      expect(Help.defang("Printer 3 won't start, 50% done")).to eq("Printer 3 won't start, 50% done")
    end

    it "breaks mentions and cross-references and escapes HTML" do
      expect(Help.defang("@a @b/c #1 <b>")).to eq("@\u200Da @\u200Db/c #\u200D1 &lt;b&gt;")
    end
  end

  it "always defangs the text of the public GitHub issue" do
    seen = nil
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { |_s, **kw| seen = kw; { number: 1 } }
    help = Help.create!(valid_attrs(name: "Pat @x", subject: "About #12 and more", comments: "hi @someone #1"))
    help.file_issue
    expect(seen).to eq(reporter: "Pat @\u200Dx", title: "About #\u200D12 and more", body: "hi @\u200Dsomeone #\u200D1")
  end

  describe "#mail_copies" do
    it "queues the mails once and records when" do
      help = Help.create!(valid_attrs)
      expect { help.mail_copies }.to have_enqueued_mail(MsrMailer, :issue_email_to_team).once
      expect(help.reload.mailed_at).to be_present
      expect { Help.find(help.id).mail_copies }.not_to have_enqueued_mail
    end
  end

  describe "#queue_filing" do
    it "queues the filing job" do
      help = Help.create!(valid_attrs)
      expect(help.queue_filing).to be(true)
      expect(HelpFilingJob).to have_been_enqueued.with(help.id)
    end

    it "reports a queue that cannot take the job and keeps the row unfinished" do
      help = Help.create!(valid_attrs)
      allow(HelpFilingJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
      expect(Rails.error).to receive(:report)
        .with(an_instance_of(ActiveJob::EnqueueError), hash_including(handled: true, context: hash_including(help_id: help.id)))
      expect(help.queue_filing).to be(false)
      expect(Help.unfinished).to include(help)
    end
  end
end
