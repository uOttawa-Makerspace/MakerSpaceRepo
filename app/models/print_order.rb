# frozen_string_literal: true

class PrintOrder < ApplicationRecord
  belongs_to :user
  has_one_attached :file
  validates :file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary\r\n", 'model/x.stl-binary'],
      if: -> {file.attached?},
  }
  #has_attached_file :file, headers: { 'Content-Disposition' => 'attachment' }
  #validates_attachment_content_type :file, content_type: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary\r\n", 'model/x.stl-binary', Paperclip::ContentTypeDetector::SENSIBLE_DEFAULT]
  #validates_attachment :file,
  #                     size: { in: 0..150.megabytes }



  has_one_attached :final_file
  validates :final_file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary\r\n", 'model/x.stl-binary', 'text/x.gcode'],
      if: -> {final_file.attached?},
  }
end
