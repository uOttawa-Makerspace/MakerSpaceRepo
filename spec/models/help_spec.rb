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

  describe "steps run outside the row's transaction" do
    # The queue may take a job only once the current transaction commits; the mail time must not be recorded first.
    it "records no mail time when the mails fail to reach the queue after the caller's transaction" do
      help = Help.create!(valid_attrs)
      allow(ActionMailer).to receive(:deliver_all_later) do
        ActiveRecord.after_all_transactions_commit { raise ActiveRecord::ConnectionNotEstablished, "queue down" }
      end
      expect { help.mail_copies }.to raise_error(ActiveRecord::ConnectionNotEstablished)
      expect(Help.find(help.id).mailed_at).to be_nil
    end

    it "calls GitHub with no transaction or row lock of its own open" do
      help = Help.create!(valid_attrs)
      outside = Help.connection.open_transactions
      inside = nil
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue) do
        inside = Help.connection.open_transactions
        { number: 3 }
      end
      help.file_issue
      expect(inside).to eq(outside)
    end

    it "queues the mails with no transaction of its own open" do
      help = Help.create!(valid_attrs)
      outside = Help.connection.open_transactions
      inside = nil
      allow(ActionMailer).to receive(:deliver_all_later) { inside = Help.connection.open_transactions }
      help.mail_copies
      expect(inside).to eq(outside)
    end
  end

  describe "step claims" do
    it "does not run a step another run holds, and takes it again once the claim is stale" do
      help = Help.create!(valid_attrs)
      help.update_columns(filing_claimed_at: 1.minute.ago)
      expect_any_instance_of(GithubIssuesService).not_to receive(:create_issue)
      expect(help.file_issue).to be(false)
      expect(help.reload.filed_at).to be_nil
      RSpec::Mocks.space.proxy_for(GithubIssuesService).reset
    end

    it "takes a claim older than the timeout (a run that died) and finishes the step" do
      help = Help.create!(valid_attrs)
      help.update_columns(filing_claimed_at: (Help::CLAIM_TIMEOUT + 1.minute).ago)
      expect(help.file_issue).to be(true)
      expect(help.reload).to have_attributes(gh_issue_number: "111", filing_claimed_at: nil)
    end

    it "gives the claim back when the step fails or raises, so the next run can do it" do
      help = Help.create!(valid_attrs)
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
      expect(help.file_issue).to be(false)
      expect(help.reload.filing_claimed_at).to be_nil

      allow(ActionMailer).to receive(:deliver_all_later).and_raise(ActiveJob::EnqueueError, "queue down")
      expect { help.mail_copies }.to raise_error(ActiveJob::EnqueueError)
      expect(help.reload).to have_attributes(mailing_claimed_at: nil, mailed_at: nil)
    end
  end

  describe "steps done by another run" do
    it "counts a step another run finished after this row was loaded as done, and the request as finished" do
      help = Help.create!(valid_attrs)
      stale = Help.find(help.id)
      expect(help.file!).to be(true)
      expect_any_instance_of(GithubIssuesService).not_to receive(:create_issue)
      expect(ActionMailer).not_to receive(:deliver_all_later)
      expect(stale.file!).to be(true)
    end

    it "neither records nor gives back a claim that another run took over" do
      help = Help.create!(valid_attrs)
      later = 1.minute.from_now.floor(6)
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue) do
        Help.where(id: help.id).update_all(filing_claimed_at: later)
        { number: 9 }
      end
      allow(Rails.error).to receive(:report)
      help.file_issue
      expect(Help.find(help.id)).to have_attributes(filed_at: nil, gh_issue_number: nil, filing_claimed_at: later)
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(RuntimeError), handled: true, context: { help_id: help.id, step: "filed_at" }).once

      allow_any_instance_of(GithubIssuesService).to receive(:create_issue) do
        Help.where(id: help.id).update_all(filing_claimed_at: later + 1.second)
        false
      end
      Help.where(id: help.id).update_all(filing_claimed_at: nil)
      help.reload.file_issue
      expect(Help.find(help.id).filing_claimed_at).to eq(later + 1.second)
    end

    it "raises the step's own error when giving the claim back fails too, and reports that failure" do
      help = Help.create!(valid_attrs)
      allow(ActionMailer).to receive(:deliver_all_later).and_raise(ActiveJob::EnqueueError, "queue down")
      allow(Help).to receive(:where).and_wrap_original do |original, *args, **kw|
        relation = original.call(*args, **kw)
        allow(relation).to receive(:update_all).and_raise(ActiveRecord::ConnectionNotEstablished, "db down") if kw.key?(:mailing_claimed_at)
        relation
      end
      allow(Rails.error).to receive(:report)
      expect { help.mail_copies }.to raise_error(ActiveJob::EnqueueError, "queue down")
      expect(Rails.error).to have_received(:report).with(an_instance_of(ActiveRecord::ConnectionNotEstablished), hash_including(handled: true))
    end
  end

  describe "#file!" do
    it "mails, then files, and says whether the request is finished" do
      help = Help.create!(valid_attrs)
      order = []
      allow(ActionMailer).to receive(:deliver_all_later).and_wrap_original { |m, *a| order << :mail; m.call(*a) }
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { order << :issue; { number: 4 } }
      expect(help.file!).to be(true)
      expect(order).to eq(%i[mail issue])
    end

    it "is not finished while the issue is missing" do
      allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
      help = Help.create!(valid_attrs)
      expect(help.file!).to be(false)
      expect(help.mailed_at).to be_present
    end
  end

  describe ".compose and #submit" do
    let(:user) { create(:user, :regular_user, name: "Account Name", email: "account@example.test") }

    it "takes an app sender's name and email from the account, and keeps the typed ones on the web form" do
      expect(Help.compose(valid_attrs.except(:source), user: user, source: Help::APP))
        .to have_attributes(name: "Account Name", email: "account@example.test", user: user, source: "app")
      expect(Help.compose(valid_attrs.except(:source), user: user, source: Help::HELP_PAGE))
        .to have_attributes(name: "Pat", email: "pat@example.test", user: user, source: "help_page")
      expect(Help.compose(valid_attrs.except(:source), user: nil, source: Help::APP)).to have_attributes(name: "Pat", user: nil)
    end

    it "saves and queues the job, or saves and queues nothing when invalid" do
      help = Help.compose(valid_attrs.except(:source), user: nil, source: Help::APP)
      expect(help.submit).to be(true)
      expect(HelpFilingJob).to have_been_enqueued.with(help.id)
      expect(Help.compose(valid_attrs(subject: "short").except(:source), user: nil, source: Help::APP).submit).to be(false)
      expect(HelpFilingJob).to have_been_enqueued.exactly(:once)
    end

    it "still answers saved when the job cannot be queued" do
      allow(HelpFilingJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, "queue down")
      allow(Rails.error).to receive(:report)
      expect(Help.compose(valid_attrs.except(:source), user: nil, source: Help::APP).submit).to be(true)
    end
  end

  it "keeps a long subject, comments and app version in full" do
    help = Help.create!(valid_attrs(subject: "s" * 300, comments: "c" * 70_000, app_version: "v" * 80))
    expect(Help.find(help.id)).to have_attributes(subject: "s" * 300, app_version: "v" * 80)
    expect(Help.find(help.id).comments.to_plain_text.length).to eq(70_000)
  end

  it "bounds the GitHub title and body and says so, and leaves short text untouched" do
    seen = []
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { |_s, **kw| seen << kw; { number: 1 } }
    Help.create!(valid_attrs(subject: "s" * 300, comments: "c" * 70_000)).file_issue
    Help.create!(valid_attrs).file_issue
    long, short = seen
    expect(long[:title].length).to be <= Help::ISSUE_TITLE_MAX
    expect(long[:title]).to end_with(Help::TRUNCATED_TITLE)
    expect(long[:body].length).to be <= Help::ISSUE_BODY_MAX
    expect(long[:body]).to end_with(Help::TRUNCATED_BODY)
    expect(short).to include(title: "A long enough subject", body: "Something broke")
  end

  it "does not check an account's own name and email as if they were typed" do
    user = create(:user, :regular_user)
    user.update_columns(name: "A")
    expect(Help.compose(valid_attrs.except(:source, :name, :email), user: user, source: Help::APP)).to be_valid
    expect(Help.compose(valid_attrs.except(:source).merge(name: "A"), user: user, source: Help::HELP_PAGE)).not_to be_valid
  end

  it "limits a typed name and email to the API's lengths, in English and French" do
    long = Help.new(valid_attrs(name: "n" * 201, email: "#{'e' * 250}@x.io"))
    expect(I18n.with_locale(:en) { long.valid?; long.errors.full_messages })
      .to include("Name is too long (maximum is 200 characters)", "Email is too long (maximum is 254 characters)")
    expect(I18n.with_locale(:fr) { long.valid?; long.errors.full_messages })
      .to include(a_string_starting_with("Nom "), a_string_starting_with("Courriel "))
    expect(Help.new(valid_attrs(name: "n" * 200))).to be_valid
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
