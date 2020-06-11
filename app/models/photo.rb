class Photo < ApplicationRecord
  belongs_to :repository

  has_attached_file :image,
                    default_url: "biomedical.jpg",
                    url: "/system/repo_images/:id/:basename.:extension"
  validates_attachment_content_type :image, :content_type => /\Aimage\/.*\Z/
end
