class Video < ActiveRecord::Base
  include Sidekiq::Worker
  belongs_to :proficient_projects
  has_attached_file :video, :styles => {
      :medium => { :geometry => "640x480", :format => 'flv' },
      :thumb => { :geometry => "100x100#", :format => 'jpg', :time => 10 }
  }, :processors => [:transcoder]
  validates_attachment_content_type :video, :content_type => /\Avideo\/.*\Z/

  #TODO: Needs to be updated
  # This was added in an attempt to use sidekiq to upload videos
  def perform(video, proficient_project_id)
    Video.create(video: video, proficient_project_id: proficient_project_id)
  end
end
