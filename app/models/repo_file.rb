# frozen_string_literal: true

class RepoFile < ApplicationRecord
  include SniffedUploadValidation

  belongs_to :repository, touch: true, optional: true
  belongs_to :proficient_project, optional: true
  belongs_to :learning_module, optional: true
  belongs_to :project_proposal, optional: true

  has_one_attached :file

  ALLOWED_CONTENT_TYPES = %w[
    application/pdf
    image/svg+xml
    text/html
    .doc
    .docx
    model/stl
    application/vnd.ms-pki.stl
    application/octet-stream
    text/plain
    model/x.stl-binary
    text/x.gcode
  ].freeze

  validates :file,
            file_content_type: {
              allow: [ALLOWED_CONTENT_TYPES],
              if: -> { file.attached? and proficient_project_id.present? }
            }
  # D-C06: every RepoFile is checked by sniffed content type and size, not only
  # those of proficient projects (which keep their narrower list).
  MAX_FILE_SIZE = 200.megabytes

  validates_sniffed_upload :file,
                           allow: ALLOWED_CONTENT_TYPES,
                           max_size: -> { MAX_FILE_SIZE },
                           if: -> { proficient_project_id.present? }
  validates_sniffed_upload :file,
                           allow: SniffedUploadValidation::GENERAL_FILE_TYPES,
                           max_size: -> { MAX_FILE_SIZE },
                           unless: -> { proficient_project_id.present? }

  validates :file, presence: true
end
