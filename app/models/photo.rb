# frozen_string_literal: true

class Photo < ApplicationRecord
  belongs_to :repository
  belongs_to :proficient_project
  belongs_to :learning_module
  belongs_to :project_proposal

  has_one_attached :image

  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/x-icon image/svg+xml].freeze

  validates :image, file_content_type: {
      allow: [ALLOWED_CONTENT_TYPES],
      if: -> {image.attached?},
  }
end
