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

  scope :not_deleted, -> { where(is_deleted: false) }

  # D-J11: emailed approve / pay links. Purpose-scoped (generates_token_for),
  # bound to the order and its owner, valid for 14 days. The approval link is
  # also bound to the latest "Waiting for User Approval" status row: a re-quote
  # retires older links, a reminder does not, and once the order moves on the
  # link is spent.
  MAGIC_LINK_TTL = 14.days

  generates_token_for :approval, expires_in: MAGIC_LINK_TTL do
    [user_id, approval_status_marker]
  end

  generates_token_for :pay, expires_in: MAGIC_LINK_TTL do
    user_id
  end

  def approval_token
    generate_token_for(:approval)
  end

  def pay_token
    generate_token_for(:pay)
  end

  # The (not soft-deleted) order a live approval / pay token was issued for,
  # else nil.
  def self.from_approval_token(token)
    not_deleted.find_by_token_for(:approval, token)
  end

  def self.from_pay_token(token)
    not_deleted.find_by_token_for(:pay, token)
  end

  def approval_status_marker
    job_order_statuses.where(job_status: JobStatus::USER_APPROVAL).maximum(:id)
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

  # Invoice URL of the Shopify draft order, creating (or re-creating) the draft when needed. Returns nil when
  # Shopify cannot be reached right now (non-200 / error payload): the stored id is then left untouched.
  # D-J38: a stored id that Shopify says no longer exists (200, `draftOrder: null`) is dropped and a fresh draft
  # is created. Kept in JobOrder (not the shared concern) so locker rentals/memberships keep their behaviour: a
  # cancelled locker must never self-heal into a fresh payable invoice.
  def checkout_link
    if shopify_draft_order_id.present?
      state, draft = fetch_shopify_draft_order_result
      return draft['invoiceUrl'] if state == :found
      return nil if state == :error
    end

    heal_draft_order_under_lock
  end

  class StaleDraftOrderError < StandardError; end

  # D-J38: called by a re-quote that changed the price. An existing Shopify draft order still carries the
  # OLD line items (and a payable invoice link), so it is deleted and the id cleared; the next /pay creates a
  # fresh draft with the new total. Fails closed (raises StaleDraftOrderError) so the caller rolls the re-quote
  # back: on a PAID/PICKED_UP order (the draft is, or is about to be, a real paid order), on any Shopify/config
  # error, and when Shopify deletes nothing (already completed/paid draft, userErrors, unknown id).
  def discard_stale_draft_order!(status_before_requote)
    return if shopify_draft_order_id.blank?

    if [JobStatus::PAID, JobStatus::PICKED_UP].include?(status_before_requote)
      raise StaleDraftOrderError, "order is already paid"
    end

    # destroy clears the id before the outcome is known; the caller's transaction rolls that back on refusal
    old_id = shopify_draft_order_id
    user_errors = []
    return if destroy_shopify_draft_order(user_errors_out: user_errors)

    # Shopify refused with userErrors (e.g. "cannot delete a completed draft"): refuse, whatever a follow-up
    # fetch says.
    raise StaleDraftOrderError, "Shopify refused to delete the draft order: #{user_errors.map { |e| e['message'] }.join(', ')}" if user_errors.present?

    # Neither a deletedId nor userErrors: the draft may simply no longer exist (dead id: treat as deleted, the
    # id is already cleared). Anything else, including a failed/raising check, refuses.
    raise StaleDraftOrderError, "Shopify did not delete the draft order" unless shopify_draft_order_gone?(old_id)
  rescue StaleDraftOrderError
    raise
  rescue StandardError => e
    raise StaleDraftOrderError, e.message
  end

  def total_price
    total = 0
    job_tasks.each do |task|
      next unless task.job_task_quote.present?
      total += task.job_task_quote.price + ((task.job_task_quote.service_price || 0) * (task.job_task_quote.service_quantity || 0))
      next unless task.job_task_quote.job_task_quote_options.any?
      task.job_task_quote.job_task_quote_options.each do |opt|
        total += opt.price || 0
      end
    end

    total += job_quote_line_items.sum(:price)

    total
  end

  def shopify_draft_order_line_items
    price_data = []

    job_tasks.each do |task|
      next unless task.job_task_quote.present?

      price_data << generate_line_item("#{task.title} Service Fee", task.job_task_quote.price)
      parts = (task.job_task_quote.service_price || 0) * (task.job_task_quote.service_quantity || 0)
      price_data << generate_line_item("#{task.title} Parts Fee", parts) if (task.job_task_quote.service_price || 0).positive? && (task.job_task_quote.service_quantity || 0).positive?

      next unless task.job_task_quote.job_task_quote_options.any?
      task.job_task_quote.job_task_quote_options.each do |opt|
        price_data << generate_line_item("#{task.title} #{opt.job_option.name}", opt.price)
      end
    end

    price_data << generate_line_item("Line Items Total", job_quote_line_items.sum(:price))

    price_data
  end

  def expedited?
    job_tasks
      .joins(job_task_options: :job_option)
      .where("job_options.name LIKE ?", "%Expedited%")
      .exists?
  end

  private

  # Row lock so two concurrent /pay requests cannot both create a draft (one would be an orphaned payable
  # invoice). After taking the lock the id is re-read: if another request already replaced it, use that draft.
  def heal_draft_order_under_lock
    url = nil
    with_lock do
      if shopify_draft_order_id.present?
        state, draft = fetch_shopify_draft_order_result
        if state == :found
          url = draft['invoiceUrl']
          next
        elsif state == :error
          next
        end
        update_column(:shopify_draft_order_id, nil) # confirmed gone
      end
      url = shopify_draft_order&.dig('invoiceUrl') # creates (Shopify call inside the lock: rare, acceptable)
    end
    url
  end

  # Amounts are normalized to BigDecimal (nil => 0) so nil/0.0 and Float/BigDecimal compare equal.
  def generate_line_item(name, unit_amount)
    unit_amount = BigDecimal((unit_amount || 0).to_s)
    {
      quantity: 1,
      title: name,
      originalUnitPriceWithCurrency: {
        amount: unit_amount,
        currencyCode: "CAD",
      }
    }
  end

  def self.shopify_draft_order_key_name
    'job_order'
  end
end
