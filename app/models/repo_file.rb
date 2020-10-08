# frozen_string_literal: true

class RepoFile < ApplicationRecord
  belongs_to :repository
  belongs_to :proficient_project
  belongs_to :learning_module

  has_one_attached :file

  validates :file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html'],
      if: -> {file.attached? and proficient_project_id.present?},
  }

end
