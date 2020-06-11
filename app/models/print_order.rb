class PrintOrder < ActiveRecord::Base
  belongs_to :user
  has_attached_file :file, :headers => { "Content-Disposition" => "attachment" }
  validates_attachment_content_type :file, :content_type => ["application/pdf", "image/svg+xml", "text/html", "model/stl", "application/vnd.ms-pki.stl", "application/octet-stream", "text/plain", "model/x.stl-binary\r\n", "model/x.stl-binary", Paperclip::ContentTypeDetector::SENSIBLE_DEFAULT]
  validates_attachment :file,
                       size: { in: 0..150.megabytes }

  has_attached_file :final_file, :headers => { "Content-Disposition" => "attachment" }
  validates_attachment_content_type :file, :content_type => ["application/pdf", "image/svg+xml", "text/html", "model/stl", "application/vnd.ms-pki.stl", "application/octet-stream", "text/plain", "model/x.stl-binary\r\n", "model/x.stl-binary", "application/x3g", Paperclip::ContentTypeDetector::SENSIBLE_DEFAULT]
  validates_attachment :final_file,
                       size: { in: 0..150.megabytes }
end