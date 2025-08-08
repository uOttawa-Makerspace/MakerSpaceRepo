class JobTaskOption < ApplicationRecord
  belongs_to :job_task
  belongs_to :job_option

  after_save :set_filename

  has_one_attached :option_file
  validates :option_file,
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
                image/png
                image/jpeg
                image/webp
              ],
              if: -> { option_file.attached? }
            }

  private

  def set_filename
    return unless option_file.attached?
      return if option_file.filename.to_s.start_with?("JMTS")
        option_file.blob.update(filename: "JMTS_#{option_file.filename}")
      
  end
end