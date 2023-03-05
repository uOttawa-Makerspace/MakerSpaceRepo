class JobService < ApplicationRecord
  belongs_to :job_service_group, optional: true
  has_and_belongs_to_many :job_orders

  validates :name, presence: true

  has_many_attached :files
  validates :files,
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
              if: -> { files.attached? }
            }

  scope :not_user_created, -> { where(user_created: false) }

  def name_with_internal_price
    "#{name} ($#{internal_price}/#{unit})"
  end

  def name_with_external_price
    "#{name} ($#{external_price}/#{unit})"
  end
end
