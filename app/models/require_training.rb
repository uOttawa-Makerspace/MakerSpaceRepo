# frozen_string_literal: true

class RequireTraining < ApplicationRecord
  belongs_to :training
  belongs_to :volunteer_task

  validates :training_id, presence: { message: 'A training must be selected' }
end
