class Video < ApplicationRecord
  include SniffedUploadValidation

  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  validate :single_parent, if: :parent_changed?

  scope :processed, -> { where(processed: true) }

  # The videos of one kind of parent (:proficient_project or :learning_module), newest first, with their files. The
  # parent is loaded for the videos that have files, the only ones the admin list shows.
  def self.listed_under(parent)
    videos = joins(parent).preload(video_attachments: :blob).order(created_at: :desc).to_a
    ActiveRecord::Associations::Preloader.new(records: videos.select { |video| video.video.attached? }, associations: parent).call
    videos
  end

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

  # the bytes themselves must be a video (no filename or declared-type
  # fallback); Marcel reports AVI as video/x-msvideo.
  SNIFFED_VIDEO_TYPES = %w[video/mp4 video/quicktime video/x-msvideo].freeze
  MAX_VIDEO_SIZE = 1.gigabyte

  validates_sniffed_upload :video,
                           allow: SNIFFED_VIDEO_TYPES,
                           max_size: -> { MAX_VIDEO_SIZE },
                           name_fallback: false

  private

  def parent_changed?
    new_record? || will_save_change_to_proficient_project_id? || will_save_change_to_learning_module_id?
  end

  def single_parent
    return if proficient_project_id.present? ^ learning_module_id.present?

    errors.add(:base, "A video belongs to either a proficient project or a learning module")
  end
end
