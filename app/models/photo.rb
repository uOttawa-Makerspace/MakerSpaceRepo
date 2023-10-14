# frozen_string_literal: true

class Photo < ApplicationRecord
  belongs_to :repository, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  belongs_to :project_proposal, optional: true
  belongs_to :volunteer_task, optional: true

  has_one_attached :image

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/gif
    image/x-icon
    image/svg+xml
  ].freeze

  validates :image,
            file_content_type: {
              allow: [ALLOWED_CONTENT_TYPES],
              if: -> { image.attached? }
            }
end
