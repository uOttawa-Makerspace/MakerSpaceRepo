# frozen_string_literal: true

class RepoFile < ApplicationRecord
  belongs_to :repository
  belongs_to :proficient_project

  has_one_attached :file

  if :proficient_project
    validates :file, file_content_type: {
        allow: ['application/pdf', 'image/svg+xml', 'text/html'],
        if: -> {file.attached?},
    }
  end


end
