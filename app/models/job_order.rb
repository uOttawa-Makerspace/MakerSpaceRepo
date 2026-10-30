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
  # else nil. Only an order with an owner has live links: the owner is the one
  # the link acts for (the approval's actor, and the actor when /pay sends the
  # order back to staff).
  def self.from_approval_token(token)
    not_deleted.where.not(user_id: nil).find_by_token_for(:approval, token)
  end

  def self.from_pay_token(token)
    not_deleted.where.not(user_id: nil).find_by_token_for(:pay, token)
  end

  # The outcome of #transition!: ok?, or refused with a reason and the message to show for it.
  #   :wrong_state         the order is not in one of `from`
  #   :link_spent          the emailed approve link was retired (re-quote / owner change) before the lock
  #   :draft_not_voidable  the destination's draft rule could not void the Shopify draft (StaleDraftOrderError)
  #   :invalid_status_row  the status row did not validate (no actor, unseeded status); reported
  TransitionResult = Data.define(:reason, :error) do
    def self.done = new(reason: nil, error: nil)
    def self.refused(reason, error = nil) = new(reason: reason, error: error)
    def ok? = reason.nil?

    def message_key
      case reason
      when :draft_not_voidable then "job_orders.alerts.status_change_draft_order_failed"
      when :invalid_status_row then "job_orders.alerts.status_change_not_recorded"
      else "job_orders.alerts.error_while_updating"
      end
    end
  end

  # JOB-02: one status transition, with one failure contract: it always returns a TransitionResult, and every
  # refusal is a result, never an exception, with nothing committed. The row is locked (the same FOR UPDATE as
  # JobOrdersController#quote and #apply_owner_change!) and the latest status is read under the lock, so a
  # transition cannot interleave with a re-quote or an owner change. `approval_token` (an emailed approve link) is
  # re-checked under the lock as well. The destination's draft rule (#enter_status!) runs in the same transaction.
  # Called inside an outer transaction (#quote), a refused result means the caller must roll back.
  def transition!(from:, to:, actor:, approval_token: nil)
    transaction do
      lock!
      latest = job_order_statuses.last&.job_status
      next TransitionResult.refused(:wrong_state) if latest.nil? || !Array.wrap(from).include?(latest)
      next TransitionResult.refused(:link_spent) if approval_token && self.class.from_approval_token(approval_token)&.id != id

      enter_status!(to, actor: actor, from: latest)
      TransitionResult.done
    end
  rescue StaleDraftOrderError => e
    TransitionResult.refused(:draft_not_voidable, e)
  rescue ActiveRecord::RecordInvalid => e
    Rails.error.report(e, handled: true, context: { job_order_id: id, where: "JobOrder#transition!", to: to&.name })
    TransitionResult.refused(:invalid_status_row, e)
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

  # The owner change's own writes did not validate (a task, an option, a custom service) or a destroy was aborted.
  # Carries the record's messages. Nothing was committed.
  class ChangeInvalid < StandardError
    def initialize(error)
      messages = error.record&.errors&.full_messages.presence
      super(messages ? messages.to_sentence : error.message)
    end
  end

  # The order could not be sent back to staff (its status row could not be written). Nothing was committed.
  class SendBackFailed < StandardError; end

  # JOB-01 (owner decision 2026-10-30): the one way the order's tasks, task options, files, services and wizard
  # comments are changed from the customer side (JobTasksController; an admin using the same wizard goes through it
  # too). The block makes the change. Under the row lock (the same FOR UPDATE as #quote and #transition!), by the
  # status read under that lock:
  # - PAID, PICKED_UP: OwnerChangeRefused, before the block runs.
  # - DRAFT, STAFF_APPROVAL, DECLINED: the change is applied; the status is unchanged.
  # - a quoted status: the change is applied and, only when it changed what is billed (#quote_fingerprint) or what
  #   is made (#work_fingerprint), the order goes back to staff in the same transaction (#send_back_for_requote!,
  #   which voids the Shopify draft, failing closed with StaleDraftOrderError) and staff are mailed after the
  #   commit. A save without changes, a blank task (no type, service, files or options: it bills nothing) and
  #   comments (posted by the caller after the commit) change neither, so they do not send the order back.
  # The block's own validation failures raise ChangeInvalid; a send-back that cannot be written raises
  # SendBackFailed. Either way nothing is committed. Returns true when the order was sent back to staff.
  def apply_owner_change!(actor:)
    sent_back = transaction do
      lock!
      status = job_order_statuses.last&.job_status
      raise OwnerChangeRefused if self.class.money_taken_status?(status)

      quoted = self.class.quoted_status?(status)
      before = change_fingerprints if quoted
      begin
        yield
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
        raise ChangeInvalid, e
      end
      next false unless quoted

      @quote_snapshot = nil # the block changed the rows the snapshot was loaded from
      next false if change_fingerprints == before

      send_back_for_requote!(actor: actor, reason: "owner_change")
      true
    end
    JobOrderMailer.send_job_requote_needed(id, "owner_change").deliver_later if sent_back
    sent_back
  end

  # Digest of what the order's tasks ask to be made, read fresh: per non-blank task (id order) its job type, service
  # (and the service's name: a custom service can be renamed), options with their files, and its user and staff
  # files. A blank task (no type, service, options or files) is left out: it neither bills nor asks for anything.
  def work_fingerprint
    tasks = job_tasks.reorder(:id).includes({ job_task_options: :option_file_attachment },
                                            :user_files_attachments, :staff_files_attachments).to_a
    service_names = JobService.where(id: tasks.filter_map(&:job_service_id)).pluck(:id, :name).to_h
    rows = tasks.filter_map do |task|
      options = task.job_task_options.map { |o| [o.job_option_id, o.option_file_attachment&.blob_id] }
                    .sort_by { |o| o.map(&:to_i) }
      files = task.user_files_attachments.map(&:blob_id).sort
      staff_files = task.staff_files_attachments.map(&:blob_id).sort
      next if task.job_type_id.nil? && task.job_service_id.nil? && options.empty? && files.empty? && staff_files.empty?

      [task.id, task.job_type_id, task.job_service_id, service_names[task.job_service_id], options, files, staff_files]
    end
    Digest::SHA256.hexdigest(rows.to_json)
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
  # JOB-03: a stored draft is served only while it is current (#draft_order_current?). Otherwise:
  # - legacy draft (stored before fingerprints existed, fingerprint NULL): nothing says whether it is stale, so it
  #   is replaced once by a draft built from the current line items, which are the ones the pay page shows. The
  #   delete fails closed: if Shopify will not delete it (e.g. already paid there) nothing is served.
  # - fingerprint mismatch: the quote changed after the draft was made without a re-quote or an owner change
  #   (both void the draft themselves), so the customer never approved the current items. Neither the old nor a
  #   new draft is served: the order goes back to staff (#send_back_for_requote!, reason "invoice_mismatch") and
  #   staff are mailed after the commit. If the draft cannot be deleted nothing changes and nothing is served.
  # Everything is decided under the row lock (with_lock reloads the row, then the status, the Shopify probe, the
  # fingerprint check and any create all read one #quote_snapshot). The Shopify calls run inside the lock; /pay is
  # low-traffic, so that is accepted.
  def checkout_link
    url, sent_back = with_lock { checkout_link_under_lock }
    JobOrderMailer.send_job_requote_needed(id, "invoice_mismatch").deliver_later if sent_back
    url
  rescue SendBackFailed
    raise # not a Shopify hiccup: the caller reports it and says so
  rescue StandardError => e
    # Timeouts, resets, session errors, create failures, a draft Shopify will not delete: the pay page shows
    # "temporarily unavailable" (no 500) and the lock's transaction has rolled back. The stored id is only ever
    # cleared for a confirmed-gone or deleted draft, so a transient error never loses it.
    Rails.error.report(e, handled: true, context: { job_order_id: id, where: "JobOrder#checkout_link" })
    nil
  end

  # JOB-03, the one staleness rule: the stored draft is current only when its fingerprint equals the fingerprint
  # of the order's quote now. A draft without a fingerprint (legacy) is never current.
  def draft_order_current?
    shopify_draft_order_fingerprint.present? && shopify_draft_order_fingerprint == quote_fingerprint
  end

  # Canonical digest of what the order bills: one [task id, component, amount] triple per money component,
  #   service fee   [task id, "service", amount]
  #   parts fee     [task id, "parts", price x quantity]       (only when both are positive, as on the draft)
  #   option fee    [task id, "option:<job_option id>", amount]
  #   line item     [0, "line_item:<job_quote_line_item id>", amount]
  # amounts as 2-decimal strings, sorted by (task id, component). Display titles (task titles, option names) are
  # not part of it, so renaming a JobOption does not change it, and row order from the database does not matter.
  def quote_fingerprint
    snapshot = quote_snapshot
    components = quote_lines.map { |line| [*line[:key], self.class.money_string(line[:amount])] }
    components += snapshot.line_items.map { |li| [0, "line_item:#{li.id}", self.class.money_string(li.price)] }
    Digest::SHA256.hexdigest(components.sort_by { |task_id, kind, _| [task_id, kind] }.to_json)
  end

  def self.money_string(amount)
    format("%.2f", BigDecimal((amount || 0).to_s).round(2))
  end

  # Everything the quote is made of, loaded once and ordered by id: the tasks with their quotes and quote options,
  # and the order's line items. total_price, the draft's line items and #quote_fingerprint all read it, so a
  # request builds it once. reload (and so lock! / with_lock) drops it. The options themselves (only their names
  # are needed, for draft titles) are preloaded by #quote_lines, once per snapshot.
  QuoteSnapshot = Data.define(:tasks, :line_items)

  def quote_snapshot
    @quote_snapshot ||= QuoteSnapshot.new(
      tasks: job_tasks.includes(job_task_quote: :job_task_quote_options).reorder(:id).to_a,
      line_items: job_quote_line_items.reorder(:id).to_a
    )
  end

  def reload(*)
    @quote_snapshot = nil
    super
  end

  class StaleDraftOrderError < StandardError; end

  # D-J38: deletes the stored Shopify draft order (stale line items and a payable invoice link) and clears the
  # id; the next /pay creates a fresh draft. Fails closed (raises StaleDraftOrderError) so the caller rolls back:
  # on any Shopify/config error, and when Shopify deletes nothing (already completed/paid draft, userErrors,
  # unknown id). Called by #enter_status! and by /pay for a legacy draft.
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
    snapshot = quote_snapshot
    tasks_total = snapshot.tasks.sum do |task|
      quote = task.job_task_quote
      next 0 if quote.nil?

      quote.price + ((quote.service_price || 0) * (quote.service_quantity || 0)) +
        quote.job_task_quote_options.sum { |opt| opt.price || 0 }
    end
    tasks_total + snapshot.line_items.sum { |li| li.price || 0 }
  end

  def shopify_draft_order_line_items
    quote_lines.map { |line| generate_line_item(line[:title], line[:amount]) } +
      [generate_line_item("Line Items Total", quote_snapshot.line_items.sum { |li| li.price || 0 })]
  end

  def expedited?
    job_tasks
      .joins(job_task_options: :job_option)
      .where("job_options.name LIKE ?", "%Expedited%")
      .exists?
  end

  private

  # JOB-03: the draft id and the fingerprint of the quote it was created from are written in one UPDATE. The line
  # items the concern sent were built from the same #quote_snapshot as #quote_fingerprint.
  def store_shopify_draft_order_id(new_id, _line_items)
    update_columns(shopify_draft_order_id: new_id, shopify_draft_order_fingerprint: quote_fingerprint)
  end

  # The task components of the quote, from #quote_snapshot, in (task id, component) order:
  # { key: [task id, component], title: draft line title, amount: BigDecimal }.
  def quote_lines
    snapshot = quote_snapshot
    unless snapshot.equal?(@quote_options_preloaded_for)
      options = snapshot.tasks.filter_map(&:job_task_quote).flat_map(&:job_task_quote_options)
      ActiveRecord::Associations::Preloader.new(records: options, associations: :job_option).call
      @quote_options_preloaded_for = snapshot
    end
    snapshot.tasks.flat_map do |task|
      quote = task.job_task_quote
      next [] if quote.nil?

      lines = [{ key: [task.id, "service"], title: "#{task.title} Service Fee", amount: quote.price }]
      if (quote.service_price || 0).positive? && (quote.service_quantity || 0).positive?
        lines << { key: [task.id, "parts"], title: "#{task.title} Parts Fee",
                   amount: quote.service_price * quote.service_quantity }
      end
      quote.job_task_quote_options.sort_by(&:job_option_id).each do |opt|
        lines << { key: [task.id, "option:#{opt.job_option_id}"], title: "#{task.title} #{opt.job_option.name}",
                   amount: opt.price }
      end
      lines
    end
  end

  # checkout_link's decision under the row lock: [invoice_url or nil, whether the order was sent back to staff].
  def checkout_link_under_lock
    latest = job_order_statuses.last&.job_status
    return [nil, false] if latest.nil? || latest != JobStatus::COMPLETED

    state, url = probe_draft_order
    return [nil, false] if state == :error
    return [url, false] if state == :found && draft_order_current?

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
  # A status row that cannot be written (e.g. no actor) raises SendBackFailed, not a task or pay-page error.
  def send_back_for_requote!(actor:, reason:)
    enter_status!(JobStatus::STAFF_APPROVAL, actor: actor, reason: reason)
  rescue ActiveRecord::ActiveRecordError => e
    raise SendBackFailed, "job order ##{id} could not be sent back to staff (#{reason}): #{e.message}"
  end

  def change_fingerprints
    [quote_fingerprint, work_fingerprint]
  end

  # The one place a status row is added (#transition!, #send_back_for_requote!, and so the quote, the owner change
  # and /pay). Caller holds the row lock. JOB-03 review 3: a live Shopify draft is a payable invoice whose URL the
  # customer may already have, whatever the order's status. So the destination decides what happens to it:
  # - COMPLETED (waiting for payment): kept; /pay serves it while it is current.
  # - PAID / PICKED_UP: kept only when Shopify reports it COMPLETED (paid through it: it is the payment record);
  #   an open draft (paid in store) is deleted so it cannot be paid a second time.
  # - every other status (re-quoted, back to staff, approved, processing, declined, reminded): deleted.
  # Deleting fails closed (StaleDraftOrderError), so a status that would leave a payable invoice behind is refused.
  def enter_status!(to, actor:, reason: nil, from: nil)
    job_order_statuses.create!(job_status: to, user: actor, reason: reason)
    return if shopify_draft_order_id.blank? || to == JobStatus::COMPLETED
    return if self.class.money_taken_status?(to) && draft_order_completed_on_shopify?

    discard_stale_draft_order!
  end

  # Whether Shopify reports the stored draft COMPLETED. Fails closed: an unanswered check raises
  # StaleDraftOrderError (the same conversion as #discard_stale_draft_order!).
  def draft_order_completed_on_shopify?
    state, draft = fetch_shopify_draft_order_result
    raise StaleDraftOrderError, "Shopify did not answer the draft order check" if state == :error

    state == :found && draft["status"] == "COMPLETED"
  rescue StaleDraftOrderError
    raise
  rescue StandardError => e
    raise StaleDraftOrderError, e.message
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
