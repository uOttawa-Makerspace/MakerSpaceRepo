# frozen_string_literal: true

class Photo < ApplicationRecord
  belongs_to :repository, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  belongs_to :project_proposal, optional: true
  belongs_to :volunteer_task, optional: true

  has_one_attached :image do |attachable|
    attachable.variant :explore, resize_to_limit: [210*2, 230*2]
    # There's no way to specify height only, so I made the width three times the
    # actual max height of 65
    attachable.variant :photo_slide, resize_to_limit: [65*3, 65]
    attachable.variant :photo_slide_first, resize_to_limit: [500*2, 500]
    attachable.variant :repo_display_wrapper, resize_to_fill: [225*2, 225*2]
  end

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
  validates :image, presence: true
end
