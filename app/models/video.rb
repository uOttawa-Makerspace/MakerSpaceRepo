class Video < ActiveRecord::Base
  belongs_to :proficient_projects
  has_attached_file :video
end
