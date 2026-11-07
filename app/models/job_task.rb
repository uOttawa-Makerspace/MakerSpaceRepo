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

  # The custom service the wizard has just made for this task (JobTasksController#use_custom_service!).
  attr_accessor :new_custom_service

  validate :job_service_belongs_to_task, if: :job_service_id_changed?

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

  private

  # A listed service must be in a group of the task's job type; a custom one must be the one just made for this task
  # or already be on a task of this order.
  def job_service_belongs_to_task
    return if job_service.blank?

    allowed =
      if job_service.user_created?
        job_service == new_custom_service || job_order.job_tasks.exists?(job_service_id: job_service.id)
      else
        job_type_id.present? && job_service.job_service_group&.job_type_id == job_type_id
      end
    errors.add(:job_service, :not_available_for_task) unless allowed
  end
end
