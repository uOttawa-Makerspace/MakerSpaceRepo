# frozen_string_literal: true

class Order < ApplicationRecord
  IN_PROGRESS = "In progress"
  COMPLETED = "Completed"
  # The order-row lock shared by checkout and every cart change.
  CART_LOCK_MODE = User::GUARD_LOCK_MODE
  before_validation :set_order_status, on: :create
  before_save :update_subtotal

  belongs_to :user, optional: true
  belongs_to :order_status, optional: true

  has_many :order_items, dependent: :destroy
  has_many :proficient_projects, through: :order_items
  has_many :cc_moneys, dependent: :destroy

  scope :completed,
        -> { joins(:order_status).where(order_statuses: { name: "Completed" }) }

  def subtotal
    order_items
      .collect { |oi| oi.valid? ? (oi.quantity * oi.unit_price) : 0 }
      .sum
  end

  def completed?
    order_status.name == "Completed"
  end

  # What each cart item's validation and charge read: loaded once for the whole cart.
  CART_ITEM_PRELOADS = [:proficient_project, { files_attachments: :blob }].freeze

  # The cart's items with their associations preloaded (no per-item queries).
  def cart_items
    return order_items.to_a if new_record?

    ActiveRecord::Associations::Preloader.new(records: [self], associations: { order_items: CART_ITEM_PRELOADS }).call
    order_items.to_a
  end

  # THE checkout total, used by both the friendly pre-check (OrdersController#check_wallet) and
  # the charge (checkout!): every item is charged its total_price (its price snapshot x quantity,
  # what the cart shows). [[item, amount], ...], or nil when an item can no longer be bought
  # (fails validation): such a cart is refused, never charged for something it did not show.
  def checkout_lines
    items = cart_items
    return nil unless items.all?(&:valid?)

    items.map { |item| [item, item.total_price.to_i] }
  end

  def checkout_total
    checkout_lines&.sum(&:last)
  end

  # The cart is no longer in progress (checked out meanwhile): its items cannot change.
  class CartClosed < StandardError; end

  # THE way to change a cart's items (add, re-quantify, remove; OrderItemsController). Its own
  # transaction: bounds lock waits, locks the order row with CART_LOCK_MODE, the lock checkout!
  # takes (an order_items INSERT/DELETE alone only takes KEY SHARE on the order, which a checkout
  # does not block), and re-checks under it that the order is still in progress, else raises
  # CartClosed (nothing written). Yields the locked order. A new (unsaved) cart has no row to
  # lock and cannot be checked out concurrently: it is yielded as is.
  def change_items!
    return yield(self) if new_record?

    self.class.own_transaction("Order#change_items!") do
      cart = self.class.lock(CART_LOCK_MODE).find(id)
      raise CartClosed unless cart.order_status&.name == IN_PROGRESS

      yield cart
    end
  end

  # Cart checkout (OrdersController#create; D-S42). Its own top-level transaction
  # (own_transaction, lock waits bounded): completes `order` for `user` and debits one CcMoney row per item through
  # CcMoney.debit_all! (one balance check for the order total, one wallet refresh). Lock order
  # (house rule): the wallet (user row) first, then the
  # order row, FOR NO KEY UPDATE, the same lock every cart change takes (change_items!), with the
  # status re-checked under it. Returns [outcome, order, kit_project_ids]:
  #   :completed          completed and paid now
  #   :already_completed  a concurrent submit of the same cart completed it (nothing debited)
  #   :not_open           any other status: an error, nothing written
  #   :invalid_items      an item can no longer be bought (checkout_lines nil): nothing written
  #   :invalid            the order did not save (nothing written)
  # Raises CcMoney::InsufficientBalance (or CcMoney::InvalidAmount for a negative price
  # snapshot) with everything rolled back. Kit mails are NOT sent here: the caller sends them
  # after the commit, for the returned kit_project_ids. A new (unsaved) order is the empty-cart
  # case (D-S04): nothing to lock, it is saved as a Completed zero-value order as before.
  def self.checkout!(order, user)
    own_transaction("Order.checkout!") do
      wallet = CcMoney.lock_wallet!(user)
      if order.persisted?
        order = lock(CART_LOCK_MODE).find(order.id)
        next [:already_completed, order, []] if order.order_status&.name == COMPLETED
        next [:not_open, order, []] unless order.order_status&.name == IN_PROGRESS
      end

      lines = order.checkout_lines
      next [:invalid_items, order, []] if lines.nil?

      order.user = wallet.user
      order.total = lines.sum(&:last)
      order.order_status = OrderStatus.find_by(name: COMPLETED)
      next [:invalid, order, []] unless order.save

      CcMoney.debit_all!(wallet, lines.map do |item, amount|
        [amount, { order: order, proficient_project: item.proficient_project }]
      end)
      items = lines.map(&:first)
      kit_project_ids = items.select { |item| item.proficient_project.has_project_kit? }.map do |item|
        ProjectKit.create!(user_id: order.user_id, proficient_project_id: item.proficient_project_id, delivered: false)
        item.proficient_project_id
      end
      [:completed, order, kit_project_ids]
    end
  end

  private

  def set_order_status
    self.order_status ||= OrderStatus.find_by(name: "In progress")
  end

  def update_subtotal
    self[:subtotal] = subtotal
  end
end
