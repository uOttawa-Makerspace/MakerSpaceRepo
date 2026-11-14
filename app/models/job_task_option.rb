class JobTaskOption < ApplicationRecord
  include PrefixedFileNames
  belongs_to :job_task
  belongs_to :job_option

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

  # Prefixes the stored name of the option file with JMTS, as set by the action that attaches it.
  def prefix_file_names
    prefix_blob_names(%i[option_file_attachment], "JMTS_", already: "JMTS")
  end
end
