# frozen_string_literal: true

# Mails the copies of a saved help request and opens its public GitHub issue (Help#file!). Queued by the request
# that saved the row (Help#submit) and again by HelpFilingSweepJob. Each step is claimed on the row before it is
# done and recorded after, so a second run, or two runs at once, mail and file once.
#
# When the request is not finished (GitHub opened no issue or could not be reached, or another run holds a step),
# the job runs again after a growing wait, ATTEMPTS runs in all; after the last one the failure is reported and the
# row is left for the sweep. A run that dies between GitHub's answer (or the mail insert) and the row update repeats
# that step once its claim times out (Help::CLAIM_TIMEOUT): GitHub takes no key that would let it recognise the
# first issue.
class HelpFilingJob < ApplicationJob
  queue_as :default

  ATTEMPTS = 3

  # Raised when a run leaves the request unfinished.
  class IssueNotFiled < StandardError; end

  retry_on IssueNotFiled, Faraday::Error, wait: :polynomially_longer, attempts: ATTEMPTS do |job, error|
    Rails.error.report(error, handled: true, context: { job: "HelpFilingJob", help_id: job.arguments.first })
  end

  def perform(help_id)
    help = Help.find_by(id: help_id)
    return unless help

    help.file! or raise IssueNotFiled, "Help request #{help_id} is not filed and mailed yet"
  end
end
