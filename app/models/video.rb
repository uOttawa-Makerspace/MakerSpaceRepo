class Video < ApplicationRecord
  include SniffedUploadValidation

  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  scope :processed, -> { where(processed: true) }

  has_many_attached :video

  ALLOWED_CONTENT_TYPES = %w[
    video/mp4
    video/avi
    video/x-msvideo
    video/mov
    video/quicktime
  ].freeze

  validates :video,
            file_content_type: {
              allow: [ALLOWED_CONTENT_TYPES],
              if: -> { video.attached? }
            }

  # D-C45: the bytes themselves must be a video (no filename or declared-type
  # fallback); Marcel reports AVI as video/x-msvideo.
  SNIFFED_VIDEO_TYPES = %w[video/mp4 video/quicktime video/x-msvideo].freeze
  MAX_VIDEO_SIZE = 1.gigabyte

  validates_sniffed_upload :video,
                           allow: SNIFFED_VIDEO_TYPES,
                           max_size: -> { MAX_VIDEO_SIZE },
                           name_fallback: false
end
