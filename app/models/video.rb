class Video < ActiveRecord::Base
  belongs_to :proficient_projects
  has_attached_file :video, :styles => {
      :medium => { :geometry => "640x480", :format => 'flv' },
      :thumb => { :geometry => "100x100#", :format => 'jpg', :time => 10 }
  }, :processors => [:transcoder]
  validates_attachment_content_type :video, :content_type => /\Avideo\/.*\Z/
end
