# frozen_string_literal: true

# A help request sent from the web help form (source help_page) or from the apps (PUT /send_email and
# POST /api/v1/support_requests, source app). The request that sends it only saves the row and queues
# HelpFilingJob; the job then mails the copies (mail_copies) and opens the public GitHub issue (file_issue). Each
# step is recorded on the row (mailed_at, filed_at) and done under a row lock, so a job that runs twice does
# neither step twice. A job that could not be queued, or that gave up, leaves the row unfinished, and
# HelpFilingSweepJob queues it again (queue_unfinished).
class Help < ApplicationRecord
  has_rich_text :comments
  belongs_to :user, optional: true

  HELP_PAGE = "help_page"
  APP = "app"
  ZWJ = "‍"

  # The sweep queues an unfinished request again when the row has not changed for this long.
  RESEND_AFTER = 15.minutes
  # Queued again this many times at most (about three hours); a request still unfinished is then reported.
  MAX_RESENDS = 12
  # Failures of the queue (its database being down, the queue refusing the job).
  QUEUE_ERRORS = [ActiveRecord::ActiveRecordError, ActiveJob::EnqueueError].freeze

  validates :name, presence: true, length: { minimum: 2 }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :subject, presence: true, length: { minimum: 10 }
  # I'd add a length check to comments but this would count HTML characters too
  validates :comments, presence: true
  validates :source, inclusion: { in: [HELP_PAGE, APP] }

  # Rows saved before the filing job existed have no source; the request that saved them did their work.
  scope :unfinished, -> { where.not(source: nil).merge(where(filed_at: nil).or(where(mailed_at: nil))) }

  # Keeps the text readable: a zero-width joiner after @ and # (and GH-) stops GitHub from
  # linking, and < > & are escaped so no raw HTML gets through.
  def self.defang(text)
    text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
        .gsub(/@(?=\w)/, "@#{ZWJ}").gsub(/#(?=\w)/, "##{ZWJ}").gsub(/\bGH-(?=\d)/i) { |m| "#{m}#{ZWJ}" }
  end

  # Queues HelpFilingJob for every unfinished request whose row has not changed for RESEND_AFTER and that was
  # queued again fewer than MAX_RESENDS times; returns how many were queued. The rows are claimed first, in one
  # statement that counts the resend and moves the row out of the due window, so an overlapping run claims none of
  # them.
  def self.queue_unfinished
    claim_unfinished.sort_by(&:id).count(&:resend)
  end

  def self.claim_unfinished
    sql = <<~SQL.squish
      UPDATE #{table_name} SET resends = resends + 1, updated_at = :now
      WHERE source IS NOT NULL AND (filed_at IS NULL OR mailed_at IS NULL)
        AND updated_at < :due_before AND resends < :max_resends
      RETURNING *
    SQL
    find_by_sql([sql, { now: Time.current, due_before: RESEND_AFTER.ago, max_resends: MAX_RESENDS }])
  end
  private_class_method :claim_unfinished

  # Queues the job that files and mails this saved request. The request is already recorded, so a queue that
  # cannot take the job is reported, not raised: the caller still answers success and the sweep queues the job
  # again. Returns whether the job was queued.
  def queue_filing
    HelpFilingJob.perform_later(id)
    true
  rescue *QUEUE_ERRORS => e
    Rails.error.report(e, handled: true, context: { job: "HelpFilingJob", help_id: id })
    false
  end

  # Opens the public GitHub issue (text defanged) and stores its number, once. Returns whether the issue exists.
  # When GitHub does not answer with an issue number nothing is stored and false is returned.
  def file_issue
    with_lock { filed_at.present? || store_issue_number }
  end

  # Queues the mails of the request, once: both or none, in one insert into the queue, the team's copy first.
  def mail_copies
    with_lock do
      next if mailed_at

      ActionMailer.deliver_all_later(*mails)
      update!(mailed_at: Time.current)
    end
  end

  def finished?
    filed_at.present? && mailed_at.present?
  end

  # Queues the job again for a row whose resend claim_unfinished already counted; the last one is reported as the
  # one after which staff have to look.
  def resend
    report_given_up if resends >= MAX_RESENDS
    queue_filing
  end

  private

  def store_issue_number
    issue = GithubIssuesService.new.create_issue(reporter: self.class.defang(name), title: self.class.defang(subject),
                                                 body: self.class.defang(comments.to_plain_text))
    number = issue && issue[:number]
    number.present? && update!(gh_issue_number: number, filed_at: Time.current)
  end

  # Signed in: a copy to the team (first) and one to the account's own address, never the typed one, which is
  # only the contact address. Guest: one mail to the team, the typed address in Reply-To.
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

  def report_given_up
    Rails.error.report(RuntimeError.new("Help request was not filed and mailed after #{MAX_RESENDS} resends"),
                       handled: true, context: { help_id: id, filed: filed_at.present?, mailed: mailed_at.present? })
  end
end
