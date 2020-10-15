class Video < ApplicationRecord
  include Sidekiq::Worker
  belongs_to :proficient_project, optional: true
  belongs_to :learning_module,    optional: true
  scope :processed, -> { where(processed: true) }

  has_one_attached :video

  ALLOWED_CONTENT_TYPES = %w[video/mp4 video/avi video/mov video/quicktime].freeze

  validates :video, file_content_type: {
      allow: [ALLOWED_CONTENT_TYPES],
      if: -> {video.attached?},
  }

end
