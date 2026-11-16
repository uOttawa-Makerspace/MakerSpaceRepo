# frozen_string_literal: true

class Photo < ApplicationRecord
  belongs_to :repository, -> { including_hidden }, touch: true, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  belongs_to :project_proposal, optional: true
  belongs_to :volunteer_task, optional: true
  scope :ordered, -> { order(position: :asc, created_at: :asc, id: :asc) }

  has_one_attached :image do |attachable|
    attachable.variant :explore, resize_to_limit: [210*2, 230*2]
    # There's no way to specify height only, so I made the width three times the
    # actual max height of 65
    attachable.variant :photo_slide, resize_to_limit: [65*3, 65]
    attachable.variant :photo_slide_first, resize_to_limit: [500*2, 500]
    attachable.variant :repo_display_wrapper, resize_to_fill: [225*2, 225*2]
  end

  MAX_IMAGE_SIZE = 10.megabytes

  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/gif
    image/x-icon
  ].freeze

  validates :image,
            file_content_type: {
              allow: [ALLOWED_CONTENT_TYPES],
              if: -> { image_changing? }
            }
  validates :image, presence: true
  validate :image_within_size_limit, if: :image_changing?

  # Raised when a posted file cannot become a photo; the message says which file and why.
  class Refused < StandardError; end

  # Creates one photo per posted file for +owner+ (for example proficient_project_id: 3), with the
  # image's measured size. Raises Refused for the first file that is unreadable or that Photo
  # refuses, so a caller inside a transaction can roll its whole save back.
  def self.create_from_uploads!(uploads, **owner)
    uploads.each { |upload| create_from_upload!(upload, **owner) }
  end

  def self.create_from_upload!(upload, **owner)
    width, height = FastImage.size(upload.tempfile, raise_on_failure: true)
    create!(image: upload, width: width, height: height, **owner)
  rescue FastImage::FastImageException
    raise Refused, I18n.t('activerecord.errors.models.photo.unreadable', filename: upload.original_filename.to_s.truncate(60))
  rescue ActiveRecord::RecordInvalid => e
    raise Refused, "#{upload.original_filename.to_s.truncate(60)}: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  def image_within_size_limit
    return if attachment_changes['image'].blob.byte_size <= MAX_IMAGE_SIZE

    errors.add(:image, :too_large, max_size: ActiveSupport::NumberHelper.number_to_human_size(MAX_IMAGE_SIZE))
  end

  # Validate only when a different blob is being attached in this save; a form that
  # posts back the blob already attached (signed_id) must not re-check a legacy image.
  # Compared by blob id against the attachment row in the database.
  def image_changing?
    change = attachment_changes['image']
    return false unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne)

    current_blob_id =
      ActiveStorage::Attachment.where(record_type: self.class.polymorphic_name, record_id: id, name: 'image').pick(:blob_id) if persisted?
    change.blob.id.nil? || change.blob.id != current_blob_id
  end
end
