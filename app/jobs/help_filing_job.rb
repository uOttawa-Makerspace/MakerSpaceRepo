# frozen_string_literal: true

# Mails the copies of a saved help request and opens its public GitHub issue (Help#mail_copies, Help#file_issue).
# Queued by the request that saved the row (Help#queue_filing) and again by HelpFilingSweepJob. Each step is
# recorded on the row and done under its lock, so a second run, or two runs at once, mail and file once.
#
# The mails go first: they do not depend on GitHub. When GitHub opens no issue, or cannot be reached, the job runs
# again after a growing wait; after the last attempt the failure is reported and the row is left for the sweep.
# A job that dies between GitHub's answer and the row's update would open a second issue on its next run (GitHub
# takes no key that would let it recognise the first).
class HelpFilingJob < ApplicationJob
  queue_as :default

  ATTEMPTS = 5

  # Raised when GitHub answered without an issue number (GithubIssuesService#create_issue returned false).
  class IssueNotFiled < StandardError; end

  retry_on IssueNotFiled, Faraday::Error, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    Rails.error.report(error, handled: true, context: { job: "HelpFilingJob", help_id: job.arguments.first })
  end

  def perform(help_id)
    help = Help.find_by(id: help_id)
    return unless help

    help.mail_copies
    raise IssueNotFiled, "GitHub opened no issue for help request #{help_id}" unless help.file_issue
  end
end
