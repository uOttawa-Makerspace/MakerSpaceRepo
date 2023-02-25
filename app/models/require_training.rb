# frozen_string_literal: true

class RequireTraining < ApplicationRecord
  belongs_to :training, optional: true
  belongs_to :volunteer_task, optional: true

  validates :training_id, presence: { message: "A training must be selected" }
end
