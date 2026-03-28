class ExtractScormJob < ApplicationJob
  queue_as :default
  # This is the default in Rails 8.2. Attachments become available after DB
  # commit
  self.enqueue_after_transaction_commit = :always

  def perform(learning_module_id)
    ScormExtractor.extract(LearningModule.find(learning_module_id))
  end
end
