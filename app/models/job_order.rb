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

  # JOB-02: one status transition. The row is locked (the same FOR UPDATE as JobOrdersController#quote and
  # #apply_owner_change!) and the latest status is read under the lock, so a transition cannot interleave with a
  # re-quote or an owner change. `approval_token` (an emailed approve link) is re-checked under the lock as well: a
  # re-quote or an owner change that committed after the link was looked up has retired it. Returns true when the
  # status row was added, false when the order is not in one of `from` (or the link is spent).
  def transition!(from:, to:, actor:, approval_token: nil)
    added = transaction do
      lock!
      latest = job_order_statuses.last&.job_status
      next false if latest.nil? || !Array.wrap(from).include?(latest)
      next false if approval_token && self.class.from_approval_token(approval_token)&.id != id
      raise ActiveRecord::Rollback unless job_order_statuses.create(job_status: to, user: actor).persisted?

      true
    end
    added == true
  end

  # JOB-04: once money has been taken the quote is final. Nothing on the customer or quoting side may change the
  # order, re-quote it or decline it; changes after payment go through staff by hand.
  # (A missing status never matches: the JobStatus constants are nil where the status rows are not seeded.)
  def self.money_taken_status?(status)
    !status.nil? && [JobStatus::PAID, JobStatus::PICKED_UP].include?(status)
  end

  # Every status a quote may be issued or declined from (all but the paid ones).
  def self.quotable_statuses
    [JobStatus::DRAFT, JobStatus::STAFF_APPROVAL, JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER,
     JobStatus::WAITING_PROCESSED, JobStatus::BEING_PROCESSED, JobStatus::COMPLETED, JobStatus::DECLINED]
  end

  # The approve link is bound to the latest quote boundary: the newest "Waiting for User Approval" row (a re-quote
  # retires older links) or "Waiting for Staff Approval" row (an order sent back for a new quote, JOB-01, retires
  # the link of the quote it replaced). A reminder moves neither, so it keeps the link.
  def approval_status_marker
    job_order_statuses.where(job_status: [JobStatus::USER_APPROVAL, JobStatus::STAFF_APPROVAL]).maximum(:id)
  end

  # Statuses in which the order carries a staff quote the customer may approve or pay.
  def self.quoted_status?(status)
    !status.nil? &&
      [JobStatus::USER_APPROVAL, JobStatus::SENT_REMINDER, JobStatus::WAITING_PROCESSED, JobStatus::BEING_PROCESSED,
       JobStatus::COMPLETED].include?(status)
  end

  class OwnerChangeRefused < StandardError; end

  # JOB-01 (owner decision 2026-10-30): the one way the order's tasks, task options, files, services and wizard
  # comments are changed from the customer side (JobTasksController; an admin using the same wizard goes through it
  # too). The block makes the change. Under the row lock (the same FOR UPDATE as #quote and #transition!), by the
  # status read under that lock:
  # - DRAFT, STAFF_APPROVAL, DECLINED: the change is applied; the status is unchanged.
  # - a quoted status: the change is applied and, in the same transaction, the order goes back to staff
  #   (#send_back_for_requote!). If the Shopify draft cannot be deleted, StaleDraftOrderError is raised and nothing
  #   is committed. Staff are mailed after the commit.
  # - PAID, PICKED_UP: OwnerChangeRefused, before the block runs.
  # Anything the block raises rolls the whole change back. Returns true when the order was sent back to staff.
  def apply_owner_change!(actor:)
    sent_back = transaction do
      lock!
      status = job_order_statuses.last&.job_status
      raise OwnerChangeRefused if self.class.money_taken_status?(status)

      yield
      next false unless self.class.quoted_status?(status)

      send_back_for_requote!(actor: actor, reason: "owner_change")
      true
    end
    JobOrderMailer.send_job_requote_needed(id, "owner_change").deliver_later if sent_back
    sent_back
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

  # Whether the order page offers `user` the wizard's Edit / Delete task / Add task buttons: the owner while the
  # order is not yet quoted, an admin until it is paid (#apply_owner_change! refuses a paid order either way).
  def task_edits_offered_to?(user)
    return !self.class.money_taken_status?(job_order_statuses.last&.job_status) if user.admin?

    allow_edit? && user.id == user_id
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

  # Invoice URL of the Shopify draft order, creating (or re-creating) the draft when needed. Returns nil when no
  # link can be served right now: Shopify cannot be reached (non-200 / error payload; the stored id is then left
  # untouched), the order is no longer COMPLETED, or the order was just sent back to staff (below).
  # D-J38: a stored id that Shopify says no longer exists (200, `draftOrder: null`) is dropped and a fresh draft
  # is created. Kept in JobOrder (not the shared concern) so locker rentals/memberships keep their behaviour: a
  # cancelled locker must never self-heal into a fresh payable invoice.
  # JOB-03: a stored draft is served only while it was built from the current line items
  # (shopify_draft_order_fingerprint, stored with the id). Otherwise, under the row lock:
  # - legacy draft (stored before fingerprints existed, fingerprint NULL): nothing says whether it is stale, so it
  #   is replaced once by a draft built from the current line items, which are the ones the pay page shows. The
  #   delete fails closed: if Shopify will not delete it (e.g. already paid there) nothing is served.
  # - fingerprint mismatch: the line items changed after the draft was made without a re-quote or an owner change
  #   (both replace the draft themselves), so the customer never approved the current items. Neither the old nor a
  #   new draft is served: the order goes back to staff (#send_back_for_requote!, reason "invoice_mismatch") and
  #   staff are mailed after the commit. If the draft cannot be deleted nothing changes and nothing is served.
  def checkout_link
    state, url = probe_draft_order
    return url if state == :found && draft_order_built_from_current_line_items?
    return nil if state == :error

    # with_lock reloads the row, so the status and the probe are repeated under the lock (the safety re-check).
    # The Shopify create runs inside the lock; this path is rare, so that is accepted.
    url, sent_back = with_lock { checkout_link_under_lock }
    JobOrderMailer.send_job_requote_needed(id, "invoice_mismatch").deliver_later if sent_back
    url
  rescue StandardError => e
    # Timeouts, resets, session errors, create failures, a draft Shopify will not delete: the pay page shows
    # "temporarily unavailable" (no 500) and the lock's transaction has rolled back. The stored id is only ever
    # cleared for a confirmed-gone or deleted draft, so a transient error never loses it.
    Rails.error.report(e, handled: true, context: { job_order_id: id, where: "JobOrder#checkout_link" })
    nil
  end

  # Whether the stored draft does not carry the current line items. JOB-03: judged by the draft's fingerprint, so a
  # draft that went stale earlier (and that /pay refuses) is replaced by a re-quote at the same prices instead of
  # surviving it. A legacy draft (no fingerprint) is judged against `legacy_baseline`, the line items before this
  # change (/pay replaces legacy drafts anyway).
  def draft_order_stale?(legacy_baseline)
    return false if shopify_draft_order_id.blank?
    return shopify_draft_order_line_items != legacy_baseline if shopify_draft_order_fingerprint.blank?

    !draft_order_built_from_current_line_items?
  end

  # Digest of draft order line items (shopify_draft_order_line_items shape). Amounts are BigDecimal, so 29.99 and
  # 29.990 give the same digest.
  def self.line_items_fingerprint(line_items)
    Digest::SHA256.hexdigest(line_items.to_json)
  end

  class StaleDraftOrderError < StandardError; end

  # D-J38: called by a re-quote that changed the price. An existing Shopify draft order still carries the
  # OLD line items (and a payable invoice link), so it is deleted and the id cleared; the next /pay creates a
  # fresh draft with the new total. Fails closed (raises StaleDraftOrderError) so the caller rolls the re-quote
  # back: on any Shopify/config error, and when Shopify deletes nothing (already completed/paid draft,
  # userErrors, unknown id). Callers refuse a paid order (JobOrder.money_taken_status?) before calling this.
  def discard_stale_draft_order!
    return if shopify_draft_order_id.blank?

    # destroy clears the id before the outcome is known; the caller's transaction rolls that back on refusal
    old_id = shopify_draft_order_id
    user_errors = []
    return if destroy_shopify_draft_order(user_errors_out: user_errors)

    # No deletedId (with or without userErrors; Shopify may report a vanished draft as "not found"): one fetch
    # decides. Proceed ONLY when Shopify confirms the draft is gone (200, no errors, draftOrder null; the id is
    # already cleared). A found (completed/paid) draft or a failed/raising fetch refuses, fail closed.
    return if shopify_draft_order_gone?(old_id)

    detail = user_errors.map { |e| e['message'] }.join(', ')
    raise StaleDraftOrderError, "Shopify did not delete the draft order#{": #{detail}" if detail.present?}"
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

  # JOB-03: the draft id and the fingerprint of the items it was created with are written in one UPDATE.
  def store_shopify_draft_order_id(new_id, line_items)
    update_columns(shopify_draft_order_id: new_id,
                   shopify_draft_order_fingerprint: self.class.line_items_fingerprint(line_items))
  end

  def draft_order_built_from_current_line_items?
    shopify_draft_order_fingerprint.present? &&
      shopify_draft_order_fingerprint == self.class.line_items_fingerprint(shopify_draft_order_line_items)
  end

  # checkout_link's decision under the row lock: [invoice_url or nil, whether the order was sent back to staff].
  def checkout_link_under_lock
    latest = job_order_statuses.last&.job_status
    return [nil, false] if latest.nil? || latest != JobStatus::COMPLETED

    state, url = probe_draft_order
    return [nil, false] if state == :error
    return [url, false] if state == :found && draft_order_built_from_current_line_items?

    if state == :found && shopify_draft_order_fingerprint.present?
      send_back_for_requote!(actor: user, reason: "invoice_mismatch")
      return [nil, true]
    end

    # a legacy draft is deleted (fail closed); a confirmed-gone id is dropped
    if state == :found
      discard_stale_draft_order!
    elsif shopify_draft_order_id.present?
      update_column(:shopify_draft_order_id, nil)
    end
    [create_draft_order_keeping_id, false]
  end

  # Inside a transaction holding the row lock: the order's quote no longer describes it. A "Waiting for Staff
  # Approval" row records who and why (which also retires the approve link, see #approval_status_marker), and the
  # Shopify draft (its payable invoice) is deleted, failing closed with StaleDraftOrderError so the caller's
  # transaction rolls back. Callers mail staff after the commit.
  def send_back_for_requote!(actor:, reason:)
    job_order_statuses.create!(job_status: JobStatus::STAFF_APPROVAL, user: actor, reason: reason)
    discard_stale_draft_order!
  end

  # [:found, invoice_url] | [:gone, nil] (blank id or Shopify says it no longer exists) | [:error, nil]
  def probe_draft_order
    return [:gone, nil] if shopify_draft_order_id.blank?

    state, draft = fetch_shopify_draft_order_result
    [state, state == :found ? draft['invoiceUrl'] : nil]
  end

  # Creates the draft. The id is stored (update_column) right after Shopify accepts the create; if the follow-up
  # fetch then raises, swallow that so the surrounding with_lock transaction COMMITS the id (a rolled-back id
  # would orphan a payable draft and the next /pay would create a second one). A failure BEFORE the id is
  # stored propagates.
  def create_draft_order_keeping_id
    shopify_draft_order&.dig('invoiceUrl')
  rescue StandardError => e
    raise if shopify_draft_order_id.blank?

    Rails.error.report(e, handled: true, context: { job_order_id: id, where: "JobOrder#create follow-up fetch" })
    nil
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
