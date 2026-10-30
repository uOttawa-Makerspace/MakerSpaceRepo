# frozen_string_literal: true

class Order < ApplicationRecord
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

  # Cart checkout (OrdersController#create; D-S42): completes `order` for `user` and debits one
  # CcMoney row per item through CcMoney.debit!, all in ONE transaction. Lock order (house
  # rule): the wallet (user row) first, then the order row (FOR NO KEY UPDATE), whose status is
  # re-checked under the lock so two submits of one cart cannot both complete and debit it.
  # Returns [:completed, order, kit_project_ids], [:already_completed, order, []] or
  # [:invalid, order, []]; raises CcMoney::InsufficientBalance (everything rolled back) when the
  # wallet does not cover an item. Kit mails are NOT sent here: the caller sends them after the
  # commit, for the returned kit_project_ids. A new (unsaved) order is the empty-cart case
  # (D-S04): nothing to lock, it is saved as a Completed zero-value order as before.
  def self.checkout!(order, user)
    transaction do
      locked_user = CcMoney.lock_wallet!(user)
      if order.persisted?
        order = lock(User::GUARD_LOCK_MODE).find(order.id)
        next [:already_completed, order, []] unless order.order_status&.name == "In progress"
      end

      order.user = locked_user
      order.total = order.subtotal
      order.order_status = OrderStatus.find_by(name: "Completed")
      next [:invalid, order, []] unless order.save

      kit_project_ids = []
      order.order_items.each do |order_item|
        CcMoney.debit!(locked_user, order_item.total_price.to_i,
                       order: order, proficient_project: order_item.proficient_project)
        next unless order_item.proficient_project.has_project_kit?

        ProjectKit.create!(user_id: order.user_id, proficient_project_id: order_item.proficient_project_id,
                           delivered: false)
        kit_project_ids << order_item.proficient_project_id
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
