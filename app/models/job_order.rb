class JobOrder < ApplicationRecord
  include ShopifyConcern

  belongs_to :user, optional: true
  belongs_to :job_type, optional: true
  belongs_to :job_service_group, optional: true
  belongs_to :job_order_quote, dependent: :destroy, optional: true
  has_many :job_order_options, dependent: :destroy
  has_many :job_order_statuses, dependent: :destroy
  has_and_belongs_to_many :job_services
  has_many :chat_messages, dependent: :destroy
  belongs_to :assigned_staff, class_name: "User", optional: true

  has_many :job_tasks, dependent: :destroy
  has_many :job_quote_line_items, dependent: :destroy

  after_save :set_filename

  scope :without_drafts,
        -> {
          joins(:job_order_statuses)
            .where(
              "job_order_statuses.created_at = (SELECT MAX(job_order_statuses.created_at) FROM job_order_statuses WHERE job_order_statuses.job_order_id = job_orders.id)"
            )
            .where.not(job_order_statuses: { job_status: JobStatus::DRAFT })
            .group("job_orders.id")
        }

  scope :order_by_expedited,
        -> {
          left_joins(:job_order_options).order(
            Arel.sql(
              "
        job_option_id = '#{JobOption.find_by(name: "Expedited").id}'
      "
            )
          ).group("job_order_options.job_option_id")
        }

  scope :not_deleted, -> { where(is_deleted: false) }

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
        unless user_files.filename.to_s.start_with?(id.to_s)
          user_files.blob.update(filename: "#{id}_#{user_files.filename}")
        end
      end
    end

    return unless staff_files.attached?
      staff_files.each do |staff_files|
        unless staff_files.filename.to_s.start_with?(id.to_s)
          staff_files.blob.update(filename: "#{id}_#{staff_files.filename}")
        end
      end
    
  end

  def allow_edit?
    [JobStatus::DRAFT, JobStatus::STAFF_APPROVAL].include?(job_order_statuses.last.job_status)
  end

  def add_options(params)
    success = true

    params.permit!

    ids = []

    params.to_h.each do |key, value|
      next unless key.include?("options_id_")
      ids << value
      if job_order_options.where(job_option_id: value).present?
        if JobOption.find(value).need_files? && !params["options_keep_file_" + value].present?
            job_order_options
              .where(job_option_id: value)
              .first
              .option_file
              .purge
          end
      else
        option = JobOrderOption.create(job_order_id: id, job_option_id: value)
        if params["options_file_" + value].present?
          option.option_file.attach(params["options_file_" + value])
          success = true unless save
        end
        job_order_options << option
        success = true unless save
      end
    end
    job_order_options.where.not(job_option_id: ids).destroy_all

    success
  end

  def max_step
    if job_type_id.present? && user_id.present?
      if (
           (job_service_group_id.present? && job_services.present?) ||
             JobServiceGroup.where(job_type_id: job_type_id).count == 0
         ) && user_files.attached?
        5
      else
        2
      end
    else
      1
    end
  end

  def checkout_link
    # @stripe_session =
      #   Stripe::Checkout::Session.create(
      #     success_url: stripe_success_job_orders_url,
      #     cancel_url: stripe_cancelled_job_orders_url,
      #     mode: "payment",
      #     line_items: @job_order.generate_line_items,
      #     billing_address_collection: "required",
      #     client_reference_id: "job-order-#{@job_order.id}"
      #   )

    shopify_draft_order['invoiceUrl']
  end

  def total_price
    job_tasks.includes(:job_task_quote).sum do |job_task|
 job_task.job_task_quote&.total_task_price.to_f end + job_quote_line_items.sum(:price)
  end

  def shopify_draft_order_line_items
    price_data = [
      generate_line_item("Service Fees", job_order_quote.service_fee)
    ]

    job_order_quote.job_order_quote_services.each do |s|
      price_data << generate_line_item(
        "#{s.job_service.job_service_group.name} - #{s.job_service.name} (#{s.quantity} #{s.job_service.unit.presence || "unit"})",
        s.cost
      )
    end
    job_order_quote.job_order_quote_options.each do |o|
      price_data << generate_line_item(o.job_option.name, o.amount)
    end

    price_data
  end

  def expedited?
    job_order_options
      .joins(:job_option)
      .where(job_option: { name: "Expedited" })
      .present?
  end

  private

  def generate_line_item(name, unit_amount)
    {
      quantity: 1,
      title: name,
      originalUnitPriceWithCurrency: {
        amount: unit_amount,
        currencyCode: "CAD",
      }
    }
  end

  def shopify_draft_order_key_name
    'job_order'
  end
end
