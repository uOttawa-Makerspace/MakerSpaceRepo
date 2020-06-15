# frozen_string_literal: true

class RepoFile < ApplicationRecord
  belongs_to :repository
  belongs_to :proficient_project

  has_attached_file :file,
                    url: '/system/repo_files/:id/:basename.:extension'
  validates_attachment_content_type :file, content_type: %r{\A*/.*\Z}
end
