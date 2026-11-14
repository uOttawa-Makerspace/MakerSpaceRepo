class JobTask < ApplicationRecord
  include PrefixedFileNames
  belongs_to :job_order
  belongs_to :job_type, optional: true
  belongs_to :job_service, optional: true
  has_many :job_task_options, dependent: :destroy
  has_many :job_options, through: :job_task_options

  # Tasks with an option whose name contains "Expedited".
  scope :expedited, -> { joins(job_task_options: :job_option).where("job_options.name LIKE ?", "%Expedited%") }
  accepts_nested_attributes_for :job_task_options, allow_destroy: true

  has_one :job_task_quote, dependent: :destroy

  delegate :user, to: :job_order

  # True when the task has no job type, or its job type offers services and none is chosen.
  def missing_information?
    job_type.blank? || (job_type.job_service_groups.any? && job_service.blank?)
  end

  # True when the task has a service line (a job service) whose price is missing. A price of 0 is a price; blank
  # is not. The service quantity does not count as a service line: a quote row starts with quantity 1 by default,
  # and the quote form only offers the service fields for a task that has a job service.
  # The quote is read first so a preloaded quote is always used, even for a task without a job service.
  def service_price_missing?
    job_task_quote&.service_price.nil? && job_service_id.present?
  end

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

  # Prefixes the stored names of this task's files, and of its options' files, as set by the actions that attach
  # them, once the save has committed.
  def prefix_file_names
    prefix_blob_names(%w[user_files staff_files], "#{job_order_id}_")
    JobTaskOption.where(job_task_id: id).each(&:prefix_file_names)
  end

  # For each of the given options, the lowest-id other task of the order that has it selected, as
  # { job_option_id => task id }. Options no other task selected are absent.
  def other_task_ids_using(option_ids)
    job_order.job_tasks.where.not(id: id).joins(:job_task_options)
             .where(job_task_options: { job_option_id: option_ids })
             .group("job_task_options.job_option_id").minimum("job_tasks.id")
  end

  # This task's row of JobOrder#work_fingerprint: its id, job type, service and the service's name (from
  # +service_names+, by service id), options with their files, and its user and staff files, each sorted. A blank
  # task (no type, service, options or files) has none.
  def work_fingerprint_row(service_names)
    parts = [fingerprint_options, *fingerprint_files]
    return if job_type_id.nil? && job_service_id.nil? && parts.all?(&:empty?)

    [id, job_type_id, job_service_id, service_names[job_service_id], *parts]
  end

  private

  # The blob ids of the task's user files and of its staff files, each sorted.
  def fingerprint_files
    [user_files_attachments.map(&:blob_id).sort, staff_files_attachments.map(&:blob_id).sort]
  end

  # Each option as [job option id, its file's blob id or nil], sorted by both (nil first).
  def fingerprint_options
    job_task_options.map { |o| [o.job_option_id, o.option_file_attachment&.blob_id] }.sort_by { |o| o.map(&:to_i) }
  end

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
