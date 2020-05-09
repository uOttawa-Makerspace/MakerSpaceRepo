class Photo < ActiveRecord::Base
  belongs_to :repository
  belongs_to :proficient_project

  has_attached_file :image,
                    default_url: "biomedical.jpg",
                    url: "/system/repo_images/:id/:basename.:extension"
  validates_attachment_content_type :image, :content_type => /\Aimage\/.*\Z/
end
