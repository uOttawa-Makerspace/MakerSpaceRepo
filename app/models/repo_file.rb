# frozen_string_literal: true

class RepoFile < ApplicationRecord
  belongs_to :repository, optional: true
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
  validates :file, presence: true
end
