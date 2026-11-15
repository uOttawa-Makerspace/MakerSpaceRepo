# frozen_string_literal: true

# A help request sent from the web help form (source help_page) or from the apps (PUT /send_email and
# POST /api/v1/support_requests, source app). The request that sends it only saves the row and queues
# HelpFilingJob (submit); the job then mails the copies and opens the public GitHub issue (file!).
#
# Each step is done once: a run first claims the step in one UPDATE, does it with no transaction or lock open, and
# only then records it (mailed_at, filed_at). A step that fails gives its claim back; a claim older than
# CLAIM_TIMEOUT (a run that died) can be taken again. A job that could not be queued, or that gave up, leaves the
# row unfinished, and HelpFilingSweepJob queues it again (queue_unfinished).
class Help < ApplicationRecord
  has_rich_text :comments
  belongs_to :user, optional: true

  HELP_PAGE = "help_page"
  APP = "app"
  ZWJ = "‍"

  # Longest values kept; the /api/v1 contract uses the same limits.
  MAX_LENGTH = { name: 200, email: 254, subject: 200 }.freeze
  # A claim on a step is taken again after this long: longer than the GitHub calls can take (see GithubIssuesService).
  CLAIM_TIMEOUT = 5.minutes
  # The sweep queues an unfinished request again when the row has not changed for this long.
  RESEND_AFTER = 15.minutes
  # Queued again this many times at most (about an hour and a half); the claim after the last one reports the
  # request and leaves it for staff. With HelpFilingJob::ATTEMPTS that is at most 21 runs per request.
  MAX_RESENDS = 6
  # Failures of the queue (its database being down, the queue refusing the job).
  QUEUE_ERRORS = [ActiveRecord::ActiveRecordError, ActiveJob::EnqueueError].freeze
  # Rows saved before the filing job existed have no source; the request that saved them did their work.
  UNFINISHED = "source IS NOT NULL AND (filed_at IS NULL OR mailed_at IS NULL)"

  validates :name, presence: true, length: { minimum: 2, maximum: MAX_LENGTH[:name] }
  validates :email, presence: true, length: { maximum: MAX_LENGTH[:email] },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true, length: { minimum: 10, maximum: MAX_LENGTH[:subject] }
  # I'd add a length check to comments but this would count HTML characters too
  validates :comments, presence: true
  validates :source, inclusion: { in: [HELP_PAGE, APP] }

  scope :unfinished, -> { where(UNFINISHED) }

  # Keeps the text readable: a zero-width joiner after @ and # (and GH-) stops GitHub from
  # linking, and < > & are escaped so no raw HTML gets through.
  def self.defang(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        .gsub(/@(?=\w)/, "@#{ZWJ}").gsub(/#(?=\w)/, "##{ZWJ}").gsub(/\bGH-(?=\d)/i) { |m| "#{m}#{ZWJ}" }
  end

  # A request from +user+ (nil for a guest). From the apps a signed-in sender's name and email are the account's;
  # on the web form the typed ones are kept as the contact details.
  def self.compose(fields, user:, source:)
    fields = fields.merge(name: user.name, email: user.email) if user && source == APP
    new(fields.merge(user: user, source: source))
  end

  # Queues HelpFilingJob for every unfinished request whose row has not changed for RESEND_AFTER, at most
  # MAX_RESENDS times each, and reports the ones claimed once more after that; returns how many were queued.
  # The rows are claimed first, in one statement that counts the claim and moves the row out of the due window,
  # so an overlapping run claims none of them.
  def self.queue_unfinished
    given_up, due = claim_unfinished.sort_by(&:id).partition { |help| help.resends > MAX_RESENDS }
    given_up.each(&:report_given_up)
    due.count(&:requeue)
  end

  def self.claim_unfinished
    sql = <<~SQL.squish
      UPDATE #{table_name} SET resends = resends + 1, updated_at = :now
      WHERE #{UNFINISHED} AND updated_at < :due_before AND resends <= :max_resends
      RETURNING *
    SQL
    find_by_sql([sql, { now: Time.current, due_before: RESEND_AFTER.ago, max_resends: MAX_RESENDS }])
  end
  private_class_method :claim_unfinished

  # Saves the request and queues its job. Returns whether it was saved: a job that cannot be queued does not
  # change that (queue_filing reports it and the sweep queues it again).
  def submit
    return false unless save

    queue_filing
    true
  end

  # Queues the job that files and mails this saved request. Returns whether the job was queued; a queue that
  # cannot take it is reported, not raised.
  def queue_filing
    HelpFilingJob.perform_later(id)
    true
  rescue *QUEUE_ERRORS => e
    Rails.error.report(e, handled: true, context: { job: "HelpFilingJob", help_id: id })
    false
  end
  alias requeue queue_filing

  # Does what is left: the mails first (they do not wait for GitHub), then the GitHub issue. Returns whether the
  # request is finished.
  def file!
    mail_copies
    file_issue
    finished?
  end

  # Queues the mails, both or none, in one insert into the queue, the team's copy first; once.
  def mail_copies
    run_once(:mailed_at, :mailing_claimed_at) do
      ActionMailer.deliver_all_later(*mails)
      {}
    end
  end

  # Opens the public GitHub issue (text defanged) and stores its number; once. Returns whether the issue exists.
  def file_issue
    run_once(:filed_at, :filing_claimed_at) do
      issue = GithubIssuesService.new.create_issue(reporter: self.class.defang(name), title: self.class.defang(subject),
                                                   body: self.class.defang(comments.to_plain_text))
      number = issue && issue[:number]
      { gh_issue_number: number } if number.present?
    end
  end

  def finished?
    filed_at.present? && mailed_at.present?
  end

  def report_given_up
    Rails.error.report(RuntimeError.new("Help request was not filed and mailed after #{MAX_RESENDS} resends"),
                       handled: true, context: { help_id: id, filed: filed_at.present?, mailed: mailed_at.present? })
  end

  private

  # Claims the step, runs the block outside any transaction and records what it returns with the step's time
  # (nil: not done, the claim is given back). Returns whether the step is done; false also when another run holds
  # the claim.
  def run_once(done, claim, &)
    return true if self[done]
    return false unless claim_step(done, claim)

    record_step(done, claim, run_claimed(claim, &))
  end

  def claim_step(done, claim)
    now = Time.current
    column = self.class.arel_table[claim]
    open = self.class.where(id: id, done => nil).where(column.eq(nil).or(column.lt(now - CLAIM_TIMEOUT)))
    open.update_all(claim => now) == 1
  end

  # A step that raises gives its claim back, so the next run does not wait for CLAIM_TIMEOUT; the error is raised.
  def run_claimed(claim)
    yield
  rescue StandardError
    update_columns(claim => nil)
    raise
  end

  def record_step(done, claim, recorded)
    recorded ? update!(recorded.merge(done => Time.current, claim => nil)) : update_columns(claim => nil)
    self[done].present?
  end

  # Signed in: a copy to the team (first) and one to the account's own address, never the typed one, which is
  # only the contact address. Guest (or an account deleted since): one mail to the team, the typed address in
  # Reply-To.
  def mails
    text = comments.to_plain_text
    return [MsrMailer.issue_email_to_team(name, email, subject, text, app_version, via: via)] unless user

    args = [name, user.email, subject, text, share_email, app_version]
    %i[issue_email_copy_to_team issue_email].map { |mail| MsrMailer.public_send(mail, *args, **account_mail_options) }
  end

  # The typed address is the contact address; the web form's mails also show the account.
  def account_mail_options
    { contact_email: email, account: (user if source == HELP_PAGE) }
  end

  def via
    source == HELP_PAGE ? "the MakerRepo help page" : "the MakerRepo app"
  end
end
