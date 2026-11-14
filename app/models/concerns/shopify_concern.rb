# frozen_string_literal: true

# A record paid through ONE Shopify draft order, whose gid it stores in shopify_draft_order_id (LockerRental,
# Membership, JobOrder): the record-side bookkeeping of that draft (its tags, keeping or discarding a new draft under
# the row lock). Every Shopify call goes through Payments::ShopifyAdapter. Retired product by product as each moves to
# Payments checkout records.
module ShopifyConcern
  extend ActiveSupport::Concern

  # Shopify answered a metafield lookup with an error (a non-200 status, or GraphQL `errors` at any status, e.g.
  # THROTTLED or INTERNAL_SERVER_ERROR). Transient: the lookup is retried later, never read as "no metafields".
  # Raised by Payments::ShopifyAdapter::Metafields. Its name stays: processed_orders.last_error records the class name.
  class MetafieldLookupFailed < StandardError; end

  # Shopify refused the metafield lookup in a way a retry cannot change (an access or invalid-id error): the
  # caller treats the order as having no metafields and reports it. `codes` are Shopify's error codes only.
  class MetafieldLookupRejected < StandardError
    attr_reader :codes

    def initialize(codes)
      @codes = codes
      super("metafield lookup rejected (#{codes.join(', ')})")
    end
  end

  # Shopify kept open a draft it was asked to delete: it can still be paid.
  class DraftOrderNotDeleted < StandardError; end

  class_methods do
    def draft_order_processable?(tag) = draft_tag_list(tag).include?(draft_order_operating_tag)

    # A draft's tags as a list of stripped strings, whether Shopify gave an array or a comma-separated string.
    def draft_tag_list(tag)
      if tag.is_a?(String)
        tag.split(',').map(&:strip)
      elsif tag.is_a?(Array)
        tag.map(&:to_s).map(&:strip)
      else
        []
      end
    end

    def draft_order_operating_tag
      "#{Payments::ShopifyAdapter.target_tag}_#{shopify_draft_order_key_name}"
    end

    def shopify_draft_order_key_name
      raise NotImplementedError, "Must define shopify_draft_order_key_name on model including ShopifyConcern"
    end

    # The marker a model's drafts carry beside the operating tag, naming the record the draft was made for
    # ("<draft_marker_name>:<id>", Payments::ShopifyAdapter::MARKERS): what ShopifyDraftSweep reconciles by.
    def draft_marker_name
      Payments::ShopifyAdapter::MARKERS.fetch(shopify_draft_order_key_name) do
        raise NotImplementedError, "Must define draft_marker_name on a model whose drafts are swept"
      end
    end

    # The record id a draft's tags name: the one marker of this model, nil when there is none or two different ones.
    def draft_marker_record_id(tags)
      pattern = /\A#{Regexp.escape(draft_marker_name)}:(\d+)\z/
      ids = draft_tag_list(tags).filter_map { |t| pattern.match(t)&.captures&.first&.to_i }.uniq
      ids.first if ids.one?
    end

    # Whether a draft with these tags is THIS environment's draft of the record `record_id` (the one rule the sweep
    # lists by and re-verifies before it deletes).
    def marked_for?(tags, record_id) = draft_order_processable?(tags) && draft_marker_record_id(tags) == record_id
  end

  def shopify_draft_order_key_name
    self.class.shopify_draft_order_key_name
  end

  private

  # Stores the id of a draft Shopify just created. A model that writes more in the same UPDATE overrides this
  # (JobOrder: the fingerprint of the quote the draft was built from; Membership: updated_at, checkout activity).
  def store_shopify_draft_order_id(new_id)
    update_column(:shopify_draft_order_id, new_id)
  end

  # Whether the record, read again under its row lock, may still take a new draft (#keep_draft_order_id_unless_taken).
  # A model whose drafts belong to one state overrides this.
  def may_take_draft_order? = true

  # THE step that keeps a draft Shopify has just created (`new_id`, made outside any lock) or deletes it again.
  # Under the row lock, with the row read again, the id is stored (#store_shopify_draft_order_id) only when the row
  # still has no draft and the record may still take one (#may_take_draft_order?). A draft that is not stored
  # (another request stored its draft first, the record moved on, or storing failed) is deleted on Shopify once the
  # lock is released, so a record is never left with a second payable draft; a stored draft is never deleted here.
  # Afterwards the record holds the row's draft id: this one when kept, else the winner's (or none). True when kept;
  # a failure to store re-raises after the delete.
  def keep_draft_order_id_unless_taken(new_id)
    kept = store_draft_order_id_unless_taken(new_id)
    discard_unused_draft(new_id) unless kept
    kept
  end

  def store_draft_order_id_unless_taken(new_id)
    with_lock do # reloads the row: the state and the stored draft id are read now
      next false unless shopify_draft_order_id.blank? && may_take_draft_order?

      store_shopify_draft_order_id(new_id)
      true
    end
  rescue StandardError
    # Nothing stored the id (lock timeout, deadlock, lost connection; a failed COMMIT stores nothing either): the new
    # draft would be a payable invoice no record points at.
    discard_unused_draft(new_id)
    raise
  end

  # Deletes a draft no record stores, by the shared rule (Payments::ShopifyAdapter::DraftRemoval). A draft that is gone, or
  # was paid meanwhile (it became an order), needs nothing. A draft Shopify still has open, and any error asking
  # Shopify, is reported and never raised: the caller goes on with the draft the row stores.
  def discard_unused_draft(gid)
    result = Payments::ShopifyAdapter::DraftRemoval.call(gid)
    return unless result.outcome == :open

    raise DraftOrderNotDeleted,
          "Shopify did not delete the unused draft order #{gid}: #{result.user_errors.map { |e| e['message'] }.join(', ')}"
  rescue StandardError => e
    Rails.error.report(e, handled: true, severity: :error,
                          context: { "#{self.class.model_name.singular}_id": id, step: 'delete_unused_shopify_draft_order' })
  end

  included do
    private

    def ensure_can_use_draft_order
      unless has_attribute?("shopify_draft_order_id")
        raise "Model #{self.class.name} does not define a shopify_draft_order_id column"
      end

      raise "Key name must not be blank" if shopify_draft_order_key_name.blank?

      unless respond_to?(:shopify_draft_order_line_items, true)
        raise "Line items method shopify_draft_order_line_items must be defined"
      end
    end

    def shopify_draft_order
      ensure_can_use_draft_order

      if shopify_draft_order_id.blank?
        create_shopify_draft_order
      else
        fetch_shopify_draft_order
      end
    end

    def fetch_shopify_draft_order
      fetch_shopify_draft_order_result.last
    end

    # One getDraftOrder query that tells three outcomes apart: [:found, draft], [:gone, nil] (HTTP 200 with
    # `draftOrder: null` and no GraphQL errors) and [:error, nil] (non-200 or an error payload). Exceptions
    # propagate (unknown, never "gone").
    def fetch_shopify_draft_order_result(gid = shopify_draft_order_id)
      Payments::ShopifyAdapter::DraftOrders.fetch_result(gid)
    end

    # Creates a draft and keeps it unless another request stored one first, then fetches the row's draft.
    def create_shopify_draft_order
      new_id, = create_remote_draft_order
      keep_draft_order_id_unless_taken(new_id)
      fetch_shopify_draft_order
    end

    # Creates the draft on Shopify (a checkout for this record: the operating tag, the record's marker when the model
    # has one, and its id in the makerepo metafield) and returns [its gid, the line items sent, its invoice URL];
    # stores nothing, so the Shopify call runs outside any lock and the caller decides under the lock whether to keep
    # the draft (#keep_draft_order_id_unless_taken).
    def create_remote_draft_order
      lines = shopify_draft_order_line_items
      reference = Payments::Reference.new(kind: shopify_draft_order_key_name, record_id: id)
      checkout = Payments::ShopifyAdapter.new.create_checkout(lines: lines, reference: reference)
      [checkout.id, lines, checkout.pay_url]
    end
  end
end
