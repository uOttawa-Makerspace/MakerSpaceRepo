class RepoFile < ApplicationRecord
  belongs_to :repository

  has_attached_file :file,
                    url: "/system/repo_files/:id/:basename.:extension"
  validates_attachment_content_type :file, :content_type => /\A*\/.*\Z/
end
