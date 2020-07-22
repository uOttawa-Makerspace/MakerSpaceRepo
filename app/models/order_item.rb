# frozen_string_literal: true

class OrderItem < ApplicationRecord
  belongs_to :proficient_project
  belongs_to :order
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validate :product_present
  validate :order_present
  before_save :finalize
  scope :completed_order, -> { joins(order: :order_status).where(order_statuses: { name: 'Completed' }) }
  scope :in_progress, -> { where(status: 'In progress') }

  def unit_price
    if persisted?
      self[:unit_price]
    else
      proficient_project.cc
    end
  end

  def total_price
    unit_price * quantity
  end

  private

  def product_present
    errors.add(:proficient_project, 'is not valid') if proficient_project.nil?
  end

  def order_present
    errors.add(:order, 'is not a valid order.') if order.nil?
  end

  def finalize
    self[:unit_price] = unit_price
    self[:total_price] = quantity * self[:unit_price]
  end
end
