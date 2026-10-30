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

  # The outcome of a locked operation on an order (#transition!, #apply_owner_change!, #checkout_link,
  # #soft_delete!, #retire_stale_draft!): ok?, or refused with a reason. Nothing is committed on a refusal.
  #   :wrong_state         the order is not in one of `from` (or, for an owner change, money was taken)
  #   :link_spent          the emailed approve link was retired (re-quote / owner change) before the lock
  #   :draft_not_voidable  the Shopify draft could not be settled (StaleDraftOrderError; any Shopify error)
  #   :invalid_status_row  the status row did not validate or could not be written (no actor, unseeded status)
  #   :change_invalid      the caller's own writes did not validate; `error.message` holds the messages
  #   :order_missing       the order was deleted (hard, or soft) before the lock
  #   :busy                a lock wait in the operation timed out (the order's row or a row the work locks);
  #                        nothing was changed, retry
  #   :not_deletable       (soft_delete! only) the actor may not delete an order in this status
  #   :deadlock            the database chose this operation as the deadlock victim (anywhere in it); nothing was
  #                        changed in the database, retry
  # `status` is the order's latest status as read under the lock (nil when the lock was not had), so a caller
  # decides "already paid" from what the operation saw, not from a later re-read. `value` is what a successful
  # operation returns (the invoice url, whether the order was sent back, the draft outcome).
  # `error` is the exception behind a refusal made from one (reported and logged once, by JobOrder#refuse_from).
  class TransitionResult < Data.define(:reason, :error, :status, :value)
    # The reasons that have their own message (job_orders.alerts.status_change.<reason>, and for the $0 bypass
    # job_orders.alerts.zero_order_not_marked_paid.<reason>). Every other reason falls back to a generic one.
    REASONS_WITH_MESSAGE = %i[draft_not_voidable invalid_status_row order_missing busy].freeze
    # A deadlock is shown as the same "try again" as a busy row.
    MESSAGE_REASON = { deadlock: :busy }.freeze
    GENERIC_MESSAGE = "job_orders.alerts.error_while_updating"
    # The reasons a delete can be refused for (job_orders.alerts.delete_refused.<reason>).
    DELETE_REASONS = %i[draft_not_voidable order_missing busy not_deletable].freeze

    def self.done(value = nil) = new(reason: nil, error: nil, status: nil, value: value)
    def self.refused(reason, error = nil) = new(reason: reason, error: error, status: nil, value: nil)
    def ok? = reason.nil?

    # The $0 bypass in #processed: the order was already moved to Completed, so "nothing was changed" would be
    # false. Its own messages say the order is Completed and why it could not be marked Paid.
    def zero_order_message_key
      message_key("job_orders.alerts.zero_order_not_marked_paid",
                  fallback: "job_orders.alerts.zero_order_not_marked_paid.other")
    end

    # `scope` holds a message per reason in `reasons`; any other reason gets `fallback`.
    def message_key(scope = "job_orders.alerts.status_change", reasons: REASONS_WITH_MESSAGE, fallback: GENERIC_MESSAGE)
      key = MESSAGE_REASON.fetch(reason, reason)
      reasons.include?(key) ? "#{scope}.#{key}" : fallback
    end
  end

  # The order row to lock is gone (see #lock_row!); its cause is the RecordNotFound.
  class OrderMissing < StandardError
    def initialize
      super("job order row is gone")
    end
  end

  # The status row could not be written (it did not validate, or the database rejected it).
  class StatusRowInvalid < StandardError
    def initialize(error)
      super("#{error.class}: #{error.message}")
    end
  end

  # The destination of an order that is being deleted: not a status, but it has its own row in the draft rule
  # (.draft_settlement): an unpaid order's draft is deleted, a paid one's COMPLETED draft (the payment record) is kept.
  DELETED = :deleted

  # JOB-02: one status transition, with one failure contract: it always returns a TransitionResult, and every
  # refusal is a result, never an exception, with nothing committed (#locked_operation). The caller never wraps it
  # in a transaction. The latest status is read under the row lock, so a transition cannot interleave with a
  # re-quote or an owner change. `approval_token` (an emailed approve link) is re-checked under the lock as well.
  # The optional block holds the writes that must be atomic with the transition (a quote's prices): it runs under
  # the lock after the source state is checked and before the status row is written; its validation failures are
  # :change_invalid. The destination's draft rule (#enter_status!) runs in the same transaction, so a refusal undoes
  # everything: the block's writes, the status row, the draft id.
  def transition!(from:, to:, actor:, approval_token: nil, &changes)
    label = "transition! #{Array.wrap(from).map { |s| s&.name }} -> #{to&.name}"
    locked_operation(label) do |latest|
      next TransitionResult.refused(:wrong_state) if latest.nil? || !Array.wrap(from).include?(latest)
      if approval_token && self.class.from_approval_token(approval_token)&.id != id
        next TransitionResult.refused(:link_spent)
      end

      apply_change(&changes) if changes
      enter_status!(to, from: latest, actor: actor)
      TransitionResult.done
    end
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

  # The caller's own writes did not validate (a task, an option, a custom service, a quote price) or a destroy was
  # aborted. Carries the record's messages. Nothing was committed.
  class ChangeInvalid < StandardError
    def initialize(error)
      messages = error.record&.errors&.full_messages.presence
      super(messages ? messages.to_sentence : error.message)
    end
  end

  # JOB-01 (owner decision 2026-10-30): the one way the order's tasks, task options, files, services and wizard
  # comments are changed from the customer side (JobTasksController; an admin using the same wizard goes through it
  # too). The block makes the change. Under the row lock (#locked_operation, the one lock of #transition! and
  # #checkout_link too), by the status read under that lock:
  # - PAID, PICKED_UP: refused as :wrong_state, before the block runs.
  # - DRAFT, STAFF_APPROVAL, DECLINED: the change is applied; the status is unchanged.
  # - a quoted status: the change is applied and, only when it changed what is billed (#quote_fingerprint) or what
  #   is made (#work_fingerprint), the order goes back to staff in the same transaction (#enter_status!, which
  #   voids the Shopify draft, failing closed) and staff are mailed after the commit. A save without changes, a
  #   blank task (no type, service, files or options: it bills nothing) and comments (posted by the caller after the
  #   commit) change neither, so they do not send the order back.
  # Returns a TransitionResult whose value is true when the order was sent back to staff.
  def apply_owner_change!(actor:, &changes)
    result = locked_operation("apply_owner_change!") do |status|
      next TransitionResult.refused(:wrong_state) if self.class.money_taken_status?(status)

      quoted = self.class.quoted_status?(status)
      before = change_fingerprints if quoted
      apply_change(&changes)
      next TransitionResult.done(false) unless quoted

      @quote_snapshot = nil # the block changed the rows the snapshot was loaded from
      next TransitionResult.done(false) if change_fingerprints == before

      enter_status!(JobStatus::STAFF_APPROVAL, from: status, actor: actor, reason: "owner_change")
      TransitionResult.done(true)
    end
    JobOrderMailer.send_job_requote_needed(id, "owner_change").deliver_later if result.ok? && result.value
    result
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
    self.class.editable_status?(job_order_statuses.last&.job_status)
  end

  # The statuses in which the owner may still change (and delete) the order: before it is quoted.
  def self.editable_status?(status)
    !status.nil? && [JobStatus::DRAFT, JobStatus::STAFF_APPROVAL].include?(status)
  end

  # Whether `user` is the order's owner and `status` is still one the owner may change (before it is quoted).
  def editable_by_owner?(user, status)
    self.class.editable_status?(status) && user.id == user_id
  end

  # Who may delete this order in `status` (what the order page offers, enforced by #soft_delete!): an admin in any
  # status, the order's owner only while it is editable, nobody else.
  def deletable_by?(user, status)
    user.admin? || editable_by_owner?(user, status)
  end

  # Whether the order page offers `user` the wizard's Edit / Delete task / Add task buttons: the owner while the
  # order is not yet quoted, an admin until it is paid (#apply_owner_change! refuses a paid order either way).
  def task_edits_offered_to?(user)
    status = job_order_statuses.last&.job_status
    return !self.class.money_taken_status?(status) if user.admin?

    editable_by_owner?(user, status)
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
  #   new draft is served: the order goes back to staff (#enter_status!, reason "invoice_mismatch") and
  #   staff are mailed after the commit. If the draft cannot be deleted nothing changes and nothing is served.
  # A current draft is served without a lock (one fetch). Anything else is re-decided under the row lock: the lock
  # reloads the row (dropping the snapshots), then the status, the probe, the fingerprint check and any create read
  # fresh data; the Shopify calls on that path run inside the lock.
  # Returns a TransitionResult whose value is the invoice url or nil (see above); a refusal (Shopify unreachable,
  # busy row, order deleted, the send-back's status row not written) has already been reported by #refuse_from.
  def checkout_link
    # Lock-free fast path: a COMPLETED order whose stored draft is current (read without a lock) is served by one
    # fetch. A race with a change that voids the draft is safe: the void deletes it on Shopify, the fetch then finds
    # nothing and falls through to the locked path. The narrow window is a staff transition still in flight: it
    # has not yet deleted the draft, so this one fetch can still serve the link. Accepted (security review): that
    # transaction deletes the draft fail closed, so the link is dead as soon as the transition commits and a
    # refused transition leaves the order, and so the link, as it was.
    if job_order_statuses.last&.job_status == JobStatus::COMPLETED && draft_order_current?
      state, url = shopify_fail_closed { probe_draft_order }
      return TransitionResult.done(url) if state == :found
      return TransitionResult.done(nil) if state == :error
    end

    # mismatch, legacy draft, or no (live) draft: re-decide everything under the row lock
    result = locked_operation("checkout_link") { |status| checkout_link_under_lock(status) }
    return result unless result.ok?

    url, sent_back = result.value
    JobOrderMailer.send_job_requote_needed(id, "invoice_mismatch").deliver_later if sent_back
    result.with(value: url)
  rescue StaleDraftOrderError => e # the fast path's fetch (the locked path maps its own)
    refuse_from(e, :draft_not_voidable, "checkout_link")
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
  def quote_fingerprint(snapshot = quote_snapshot)
    components = quote_lines(snapshot).map { |line| [*line[:key], self.class.money_string(line[:amount])] }
    components += snapshot.line_items.map { |li| [0, "line_item:#{li.id}", self.class.money_string(li.price)] }
    Digest::SHA256.hexdigest(components.sort_by { |task_id, kind, _| [task_id, kind] }.to_json)
  end

  def self.money_string(amount)
    format("%.2f", BigDecimal((amount || 0).to_s).round(2))
  end

  # Everything the quote is made of, loaded once per request and ordered by id: the tasks with their quotes and
  # quote options, and the order's line items. ONE snapshot is read by #total_price, #quote_fingerprint and the
  # draft's line items, so they cannot disagree within a request. The options' names (JobOption) are only needed
  # for the draft's line titles, so they are preloaded onto the same rows when those are built
  # (#shopify_draft_order_line_items), not for readers that never show them. reload (and so lock!)
  # drops it.
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

  # The one place a Shopify draft that could not be settled is raised (fail closed).
  def self.stale_draft!(message, user_errors = [])
    detail = user_errors.map { |e| e['message'] }.join(', ')
    raise StaleDraftOrderError, "#{message}#{": #{detail}" if detail.present?}"
  end

  def self.not_deleted_by_shopify!(user_errors)
    stale_draft!("Shopify did not delete the draft order", user_errors)
  end

  # [:found | :gone, draft]; Shopify not answering raises (fail closed).
  def self.fetch_draft_or_raise(gid)
    state, draft = fetch_shopify_draft_order_result(gid)
    stale_draft!("Shopify did not answer the draft order check") if state == :error

    [state, draft]
  end

  # The marker every job-order draft carries (JobOrder#shopify_draft_order_tags): which order it was made for.
  DRAFT_MARKER = /\Ajob_order:(\d+)\z/

  def self.draft_marker_tag(order_id) = "job_order:#{order_id}"

  # Deletes the draft `gid` unless it is paid, whoever (if anyone) points at it: [:cleared] Shopify no longer has
  # it, [:kept] it is COMPLETED (paid: the payment record is never deleted), [:deleted]. Fail closed
  # (StaleDraftOrderError). Used by #reconcile_shopify_draft! and, for a draft whose order row is gone, by
  # JobOrder::DraftSweep.
  def self.delete_draft_unless_completed!(gid)
    state, draft = fetch_draft_or_raise(gid)
    return :cleared if state == :gone
    return :kept if draft["status"] == "COMPLETED"

    user_errors = []
    return :deleted if delete_shopify_draft_order(gid, user_errors_out: user_errors)

    not_deleted_by_shopify!(user_errors)
  end

  # One open Shopify draft `gid` that carries this order's marker, reconciled against the database (see
  # JobOrder::DraftSweep): kept only when the order is live, waiting for payment (COMPLETED) and its stored
  # shopify_draft_order_id is this draft; anything else is an orphan (a create whose transaction rolled back, a draft
  # replaced by a re-quote, an order deleted or no longer payable) and is deleted unless Shopify reports it paid.
  # One locked operation, so a create still in flight (it holds this row's lock until it commits the id) is waited
  # for and then found current, never deleted from under its transaction. TransitionResult value: :kept, :deleted
  # or :cleared.
  def reconcile_shopify_draft!(gid)
    locked_operation("reconcile_shopify_draft!", live_only: false) do |status|
      next TransitionResult.done(:kept) if !is_deleted && status == JobStatus::COMPLETED && shopify_draft_order_id == gid

      outcome = shopify_fail_closed { self.class.delete_draft_unless_completed!(gid) }
      update_column(:shopify_draft_order_id, nil) if shopify_draft_order_id == gid && outcome != :kept
      TransitionResult.done(outcome)
    end
  end

  # THE settle rule: which path settles the Shopify draft of an order going from status `from` (nil when there is
  # no transition: the rake on a live order) to `destination` (a JobStatus, or DELETED). The one place it is decided;
  # transitions, deletes and the rake all go through #settle_draft_order!.
  #   destination            from            path
  #   COMPLETED              any             :none    waiting for payment: /pay serves the draft while current
  #   any status but DELETED PAID            :none    leaving PAID: entering it already settled the draft
  #   PAID, PICKED_UP        any other       :paid    money is (being) taken
  #   DELETED                PAID, PICKED_UP :paid    money was taken: the payment record must survive the delete
  #   anything else          any             :unpaid  (re-quoted, back to staff, approved, processing, declined,
  #                                                    reminded, or a delete of an unpaid order)
  def self.draft_settlement(from, destination)
    return :none if destination == JobStatus::COMPLETED
    return :none if from == JobStatus::PAID && destination != DELETED

    money_taken_status?(destination == DELETED ? from : destination) ? :paid : :unpaid
  end

  # The draft rule for an order going from `from` to `destination` (see .draft_settlement). A live Shopify draft is
  # a payable invoice whose URL the customer may already have, whatever the order's status. The caller holds the
  # row lock; returns :kept, :deleted, :cleared, or nil when there was nothing to do.
  # - :paid: getDraftOrder first, because a draft Shopify reports COMPLETED is kept (:kept; the customer paid
  #   through it, it is the payment record), a vanished one is cleared (:cleared), an open one (paid in store) is
  #   deleted, so it cannot be paid a second time.
  # - :unpaid: the draft is deleted first, one Shopify call. Only when Shopify deleted nothing is it asked why:
  #   gone (:cleared), COMPLETED (paid: refused), anything else refused.
  # Fails closed (StaleDraftOrderError, any Shopify/config error included; database errors are not Shopify's and
  # propagate), so a destination that would leave a payable invoice behind is refused, and the caller's
  # transaction rolls back. Used by #enter_status!, #soft_delete! and #retire_stale_draft! (legacy rows).
  def settle_draft_order!(from, destination)
    path = self.class.draft_settlement(from, destination)
    return if shopify_draft_order_id.blank? || path == :none

    shopify_fail_closed { path == :paid ? settle_for_paid_order : delete_draft_unless_paid }
  end

  # Applies the draft rule to the order as it stands (rake job_orders:retire_stale_drafts), for a row written
  # before transitions and deletes settled drafts: DELETED when the order is soft-deleted, else its current status.
  # A TransitionResult whose value is the outcome of #settle_draft_order! or :skipped (no draft, no status, or
  # waiting for payment, where the draft is the invoice).
  def retire_stale_draft!
    locked_operation("retire_stale_draft!", live_only: false) do |status|
      # a deleted order always settles as a delete (an unpaid one when it has no status); a live order has no
      # transition (from nil) and, with no status, nothing to settle
      next TransitionResult.done(:skipped) if status.nil? && !is_deleted

      outcome = is_deleted ? settle_draft_order!(status, DELETED) : settle_draft_order!(nil, status)
      TransitionResult.done(outcome || :skipped)
    end
  end

  def self.retire_stale_draft!(id)
    find_by(id: id)&.retire_stale_draft! || TransitionResult.refused(:order_missing)
  end

  # The one way an order is deleted (JobOrdersController#destroy): soft delete under the row lock, with the order's
  # Shopify draft settled in the same transaction by the draft rule for DELETED (.draft_settlement): an unpaid
  # order's draft is deleted, fail closed; a paid order's (PAID, PICKED_UP) COMPLETED draft is kept as the payment
  # record, an open one deleted, a gone one cleared. A deleted order leaves no payable invoice behind and a refused
  # settle leaves it as it was. `actor` must be allowed to delete in the status read under the lock (#deletable_by?),
  # else :not_deletable. Deleting an already deleted order is :order_missing (as for every other operation).
  def soft_delete!(actor:)
    locked_operation("soft_delete!") do |status|
      next TransitionResult.refused(:not_deletable) unless deletable_by?(actor, status)

      settle_draft_order!(status, DELETED)
      update_columns(is_deleted: true, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      TransitionResult.done
    end
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
    snapshot = quote_snapshot
    preload_option_names(snapshot)
    quote_lines(snapshot, titles: true).map { |line| generate_line_item(line[:title], line[:amount]) } +
      [generate_line_item("Line Items Total", snapshot.line_items.sum { |li| li.price || 0 })]
  end

  def expedited?
    job_tasks
      .joins(job_task_options: :job_option)
      .where("job_options.name LIKE ?", "%Expedited%")
      .exists?
  end

  private

  # The one operation on a locked order (#transition!, #apply_owner_change!, #checkout_link, #soft_delete!,
  # #retire_stale_draft!): its own transaction (ApplicationRecord.own_transaction: every lock wait is bounded, and it
  # refuses to run inside a caller's transaction), the order row locked and reloaded, the latest status read under
  # the lock and yielded. The block returns a TransitionResult (done, or a refusal it decided itself).
  # Only these are turned into results:
  # - LockWaitTimeout (:busy) and Deadlocked (:deadlock), wherever in the transaction they are raised (the order
  #   row's lock, a child row's lock inside the work): both are properties of the transaction, which rolled back;
  # - the order gone (:order_missing), only from taking the order's row lock (#lock_row!);
  # - the domain errors the work raises on purpose: StaleDraftOrderError (the draft could not be settled),
  #   ChangeInvalid (#apply_change), StatusRowInvalid (#write_status_row!).
  # Anything else the work raises (a bad blob id, a NOT NULL violation in a price column) is not a refusal: it
  # rolls the transaction back and propagates.
  # A soft-deleted order is refused as :order_missing unless the operation works on deleted orders (`live_only:
  # false`): nothing may be changed on, or collect money for, a deleted order.
  # Order of work: a Shopify call cannot be rolled back, so inside an operation it is the last step that touches rows
  # other than the order's own locked row (the block's writes and the status row come first; after the Shopify call
  # only the order row, already locked, is updated). A database or lock error after a Shopify mutation still rolls
  # the transaction back while Shopify keeps the change (a created draft no order points at). That is not tracked
  # here: every job-order draft carries a marker naming its order (#shopify_draft_order_tags), and
  # JobOrder::DraftSweep (rake job_orders:sweep_orphan_drafts, run regularly by JobOrderDraftSweepJob) deletes the
  # open drafts the database does not point at.
  # On any refusal made from an exception the record is reloaded (unsaved in-memory changes do not survive it).
  def locked_operation(label, live_only: true)
    status = nil
    result = self.class.own_transaction("JobOrder##{label}") do
      lock_row!
      next TransitionResult.refused(:order_missing) if live_only && is_deleted

      status = job_order_statuses.last&.job_status
      yield status
    end
    result.with(status: status)
  rescue OrderMissing => e
    refuse_from(e.cause, :order_missing, label)
  rescue ActiveRecord::LockWaitTimeout => e
    refuse_from(e, :busy, label)
  rescue ActiveRecord::Deadlocked => e
    refuse_from(e, :deadlock, label)
  rescue StaleDraftOrderError => e
    refuse_from(e, :draft_not_voidable, label)
  rescue ChangeInvalid => e
    refuse_from(e, :change_invalid, label)
  rescue StatusRowInvalid => e
    refuse_from(e, :invalid_status_row, label)
  end

  # FOR UPDATE on the order's row, re-reading it (so the snapshots and associations are dropped). The only place
  # a RecordNotFound means "the order is gone".
  def lock_row!
    lock!
  rescue ActiveRecord::RecordNotFound
    raise OrderMissing
  end

  # What is reported: a refusal that is a bug or an outage is an error; a race lost or the caller's invalid input is
  # an info line only. A deadlock is not benign: the lock order is wrong somewhere.
  REPORTED_REFUSALS = %i[draft_not_voidable invalid_status_row deadlock].freeze

  # The one place a refusal made from an exception is reported and logged (the Shopify error behind
  # :draft_not_voidable, a status row that did not validate, the messages of :change_invalid ...). The
  # transaction has rolled back; the record is re-read so it does not keep the draft id or status row the failed
  # attempt changed in memory.
  def refuse_from(error, reason, label)
    line = "[JobOrder##{label}] ##{id} refused (#{reason}): #{error.class}: #{error.message}"
    if REPORTED_REFUSALS.include?(reason)
      context = { job_order_id: id, operation: label, reason: reason, where: "JobOrder##{label.split.first}" }
      Rails.error.report(error, handled: true, context: context)
      Rails.logger.error(line)
    else
      Rails.logger.info(line)
    end
    begin
      reload
    rescue ActiveRecord::RecordNotFound
      nil # deleted: nothing to re-read
    end
    TransitionResult.refused(reason, error)
  end

  def fetch_draft_or_raise(gid = shopify_draft_order_id)
    self.class.fetch_draft_or_raise(gid)
  end

  # Deletes the draft Shopify just reported (found, not completed-and-kept). The id is cleared with the delete;
  # the caller's transaction rolls that back on refusal. Shopify deleting nothing raises.
  def delete_found_draft!
    user_errors = []
    return :deleted if destroy_shopify_draft_order(user_errors_out: user_errors)

    self.class.not_deleted_by_shopify!(user_errors)
  end

  # A destination where the customer may already have paid through the draft: ask first (one getDraftOrder), then
  # keep a COMPLETED one, clear a vanished one, delete an open one.
  def settle_for_paid_order
    state, draft = fetch_draft_or_raise
    if state == :gone
      update_column(:shopify_draft_order_id, nil)
      :cleared
    elsif draft["status"] == "COMPLETED"
      :kept
    else
      delete_found_draft!
    end
  end

  # An unpaid destination: delete the draft (one Shopify call). When Shopify deleted nothing it is asked why
  # (the id is cleared by the delete; the caller's transaction rolls that back on refusal).
  def delete_draft_unless_paid
    gid = shopify_draft_order_id
    user_errors = []
    return :deleted if destroy_shopify_draft_order(user_errors_out: user_errors)

    state, draft = fetch_draft_or_raise(gid)
    return :cleared if state == :gone
    self.class.stale_draft!("the draft order is already paid (COMPLETED)") if draft["status"] == "COMPLETED"

    self.class.not_deleted_by_shopify!(user_errors)
  end

  # The caller's own writes, made inside the row lock: their validation failures are ChangeInvalid (nothing is
  # committed). Anything else propagates.
  def apply_change
    yield
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
    raise ChangeInvalid, e
  end

  # The one fail-closed conversion for Shopify work behind a status decision: any error (HTTP, timeout, session,
  # configuration) becomes StaleDraftOrderError, so the caller refuses and its transaction rolls back. A database
  # error is not Shopify's: it propagates as itself.
  def shopify_fail_closed
    yield
  rescue StaleDraftOrderError, ActiveRecord::ActiveRecordError
    raise
  rescue StandardError => e
    raise StaleDraftOrderError, "#{e.class}: #{e.message}"
  end

  # The environment's operating tag plus the marker that names the order (JobOrder::DraftSweep reconciles by it).
  def shopify_draft_order_tags
    [self.class.draft_order_operating_tag, self.class.draft_marker_tag(id)]
  end

  # JOB-03: the draft id and the fingerprint of the quote it was created from are written in one UPDATE. The line
  # items the concern sent were built from the same #quote_snapshot as #quote_fingerprint.
  def store_shopify_draft_order_id(new_id, _line_items)
    update_columns(shopify_draft_order_id: new_id, shopify_draft_order_fingerprint: quote_fingerprint)
  end

  def preload_option_names(snapshot)
    quote_options = snapshot.tasks.flat_map { |task| task.job_task_quote&.job_task_quote_options.to_a }
    ActiveRecord::Associations::Preloader.new(records: quote_options, associations: :job_option).call
  end

  # The task components of `snapshot`, in (task id, component) order:
  # { key: [task id, component], amount: BigDecimal, title: draft line title (only with titles:, which needs the
  # options' names preloaded, see #preload_option_names) }.
  def quote_lines(snapshot, titles: false)
    snapshot.tasks.flat_map do |task|
      quote = task.job_task_quote
      next [] if quote.nil?

      lines = [{ key: [task.id, "service"], amount: quote.price, title: titles && "#{task.title} Service Fee" }]
      if (quote.service_price || 0).positive? && (quote.service_quantity || 0).positive?
        lines << { key: [task.id, "parts"], amount: quote.service_price * quote.service_quantity,
                   title: titles && "#{task.title} Parts Fee" }
      end
      quote.job_task_quote_options.sort_by(&:job_option_id).each do |opt|
        lines << { key: [task.id, "option:#{opt.job_option_id}"], amount: opt.price,
                   title: titles && "#{task.title} #{opt.job_option.name}" }
      end
      lines
    end
  end

  # checkout_link's decision under the row lock: [invoice_url or nil, whether the order was sent back to staff].
  # Every Shopify call is fail closed (StaleDraftOrderError), so the pay page shows "temporarily unavailable" with
  # the transaction rolled back; the stored id is only ever cleared for a confirmed-gone or deleted draft, so a
  # transient error never loses it.
  def checkout_link_under_lock(latest)
    return TransitionResult.done([nil, false]) if latest.nil? || latest != JobStatus::COMPLETED

    state, url = shopify_fail_closed { probe_draft_order }
    return TransitionResult.done([nil, false]) if state == :error
    return TransitionResult.done([url, false]) if state == :found && draft_order_current?

    if state == :found && shopify_draft_order_fingerprint.present?
      enter_status!(JobStatus::STAFF_APPROVAL, from: latest, actor: user, reason: "invoice_mismatch")
      return TransitionResult.done([nil, true])
    end

    # a legacy draft is deleted (fail closed); a confirmed-gone id is dropped
    if state == :found
      shopify_fail_closed { delete_found_draft! }
    elsif shopify_draft_order_id.present?
      update_column(:shopify_draft_order_id, nil)
    end
    TransitionResult.done([shopify_fail_closed { create_draft_order_keeping_id }, false])
  end

  def change_fingerprints
    [quote_fingerprint, work_fingerprint]
  end

  # The one place a status row is added (#transition!, the owner change, /pay's send-back). Caller holds the row
  # lock. The draft is settled in the same transaction (#settle_draft_order!; an order leaving PAID needs no Shopify
  # call, so staff can record pick-ups during a Shopify outage: see .draft_settlement).
  def enter_status!(to, from:, actor:, reason: nil)
    write_status_row!(to, actor, reason)
    settle_draft_order!(from, to)
  end

  def write_status_row!(to, actor, reason)
    job_order_statuses.create!(job_status: to, user: actor, reason: reason)
  rescue ActiveRecord::RecordInvalid, ActiveRecord::NotNullViolation => e
    raise StatusRowInvalid, e
  end

  # [:found, invoice_url] | [:gone, nil] (blank id or Shopify says it no longer exists) | [:error, nil]
  def probe_draft_order
    return [:gone, nil] if shopify_draft_order_id.blank?

    state, draft = fetch_shopify_draft_order_result
    [state, state == :found ? draft['invoiceUrl'] : nil]
  end

  # Creates the draft. The id is stored (update_column) right after Shopify accepts the create; if the follow-up
  # fetch then raises (not a database error), swallow that so the surrounding locked operation COMMITS the id (a rolled-back id
  # would orphan a payable draft and the next /pay would create a second one). A failure BEFORE the id is
  # stored propagates.
  def create_draft_order_keeping_id
    shopify_draft_order&.dig('invoiceUrl')
  rescue ActiveRecord::ActiveRecordError
    raise # a database error (a lock wait, a deadlock) is not the follow-up fetch's: the operation maps or propagates it
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
