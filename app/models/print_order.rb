# frozen_string_literal: true
require "date"

class PrintOrder < ApplicationRecord
  belongs_to :user, optional: true
  after_save :set_filename

  has_one_attached :file
  validates :file,
            file_content_type: {
              allow: %w[
                application/pdf
                image/svg+xml
                text/html
                model/stl
                application/vnd.ms-pki.stl
                application/octet-stream
                text/plain
                model/x.stl-binary
                model/x.stl-binary
                text/x.gcode
                image/vnd.dxf
                image/x-dxf
                model/x.stl-ascii
              ],
              if: -> { file.attached? }
            }

  has_many_attached :final_file
  validates :final_file,
            file_content_type: {
              allow: %w[
                application/pdf
                image/svg+xml
                text/html
                model/stl
                application/vnd.ms-pki.stl
                application/octet-stream
                text/plain
                model/x.stl-binary
                model/x.stl-binary
                text/x.gcode
                image/vnd.dxf
                image/x-dxf
                model/x.stl-ascii
              ],
              if: -> { final_file.attached? }
            }

  has_one_attached :pdf_form
  validates :pdf_form,
            file_content_type: {
              allow: %w[application/pdf text/plain],
              if: -> { pdf_form.attached? }
            }

  def set_filename
    if file.attached? && !file.filename.to_s.start_with?(id.to_s)
      file.blob.update(filename: "#{id}_#{file.filename}")
    end

    if final_file.attached?
      final_file.each do |staff_files|
        unless staff_files.filename.to_s.start_with?(id.to_s)
          staff_files.blob.update(filename: "#{id}_#{staff_files.filename}")
        end
      end
    end

    if pdf_form.attached?
      if pdf_form.attached? && !pdf_form.filename.to_s.start_with?(id.to_s)
        pdf_form.blob.update(filename: "#{id}_#{pdf_form.filename}")
      end
    end
  end
end
