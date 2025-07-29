class JobTask < ApplicationRecord
  belongs_to :job_order
  belongs_to :job_type, optional: true
  belongs_to :job_service, optional: true
  has_many :job_task_options, dependent: :destroy
  has_many :job_options, through: :job_task_options
  accepts_nested_attributes_for :job_task_options, allow_destroy: true

  has_one :job_task_quote, dependent: :destroy

  delegate :user, to: :job_order

  after_save :set_filename

  has_many_attached :user_files
  validates :user_files,
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
              if: -> { user_files.attached? }
            }

  has_many_attached :staff_files
  validates :staff_files,
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
              if: -> { staff_files.attached? }
            }

  def set_filename
    if user_files.attached?
      user_files.each do |user_files|
        unless user_files.filename.to_s.start_with?(job_order.id.to_s)
          user_files.blob.update(filename: "#{job_order.id}_#{user_files.filename}")
        end
      end
    end

    return unless staff_files.attached?
      staff_files.each do |staff_files|
        unless staff_files.filename.to_s.start_with?(job_order.id.to_s)
          staff_files.blob.update(filename: "#{job_order.id}_#{staff_files.filename}")
        end
      end
  end
end
