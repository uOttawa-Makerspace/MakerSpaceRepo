# frozen_string_literal: true

# Queues HelpFilingJob again for the help requests that are not filed and mailed yet: the ones whose job could not
# be queued when the request was saved, and the ones whose job gave up (Help.queue_unfinished). Runs on a schedule
# (config/recurring.yml). Safe to run at any time and twice: it claims each row before queuing, and the job does
# each step once.
class HelpFilingSweepJob < ApplicationJob
  queue_as :default

  def perform
    Help.queue_unfinished
  end
end
