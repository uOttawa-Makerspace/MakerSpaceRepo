# frozen_string_literal: true

class PrintOrder < ApplicationRecord
  belongs_to :user
  after_save :set_filename

  has_one_attached :file
  validates :file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary", 'model/x.stl-binary', 'text/x.gcode', 'image/vnd.dxf', 'image/x-dxf'],
      if: -> {file.attached?},
  }

  has_one_attached :final_file
  validates :final_file, file_content_type: {
      allow: ['application/pdf', 'image/svg+xml', 'text/html', 'model/stl', 'application/vnd.ms-pki.stl', 'application/octet-stream', 'text/plain', "model/x.stl-binary", 'model/x.stl-binary', 'text/x.gcode', 'image/vnd.dxf', 'image/x-dxf'],
      if: -> {final_file.attached?},
  }

  def set_filename
    file.blob.update(filename: "#{id}_#{file.filename}") if file.attached? and !file.filename.to_s.start_with?(id.to_s)
    final_file.blob.update(filename: "#{id}_#{final_file.filename}") if final_file.attached? and !final_file.filename.to_s.start_with?(id.to_s)
  end

end
