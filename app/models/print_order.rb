class PrintOrder < ActiveRecord::Base
  has_attached_file :file, { validate_media_type: false }
  validates_attachment_content_type :file, :content_type => ["model/stl", "application/vnd.ms-pki.stl", "application/octet-stream", "text/plain", "model/x.stl-binary\r\n", "model/x.stl-binary", Paperclip::ContentTypeDetector::SENSIBLE_DEFAULT]
  validates_attachment :file,
                       size: { in: 0..50.megabytes }
end
