class ExtractScormJob < ApplicationJob
  queue_as :default

  def perform(learning_module_id)
    ScormExtractor.extract(LearningModule.find(learning_module_id))
  end
end
