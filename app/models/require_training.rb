# frozen_string_literal: true

class RequireTraining < ApplicationRecord
  belongs_to :training, optional: true
  belongs_to :volunteer_task

  validates :training_id, presence: true
end
