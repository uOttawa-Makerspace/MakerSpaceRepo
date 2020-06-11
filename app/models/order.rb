class Order < ActiveRecord::Base
  before_validation :set_order_status, on: :create
  before_save :update_subtotal
  belongs_to :user
  belongs_to :order_status
  has_many :order_items, dependent: :destroy
  has_many :proficient_projects, through: :order_items
  has_many :cc_moneys, dependent: :destroy
  scope :completed, -> {joins(:order_status).where(order_statuses: {name: "Completed"})}

  def subtotal
    order_items.collect { |oi| oi.valid? ? (oi.quantity * oi.unit_price) : 0 }.sum
  end

  def completed?
    self.order_status.name == "Completed"
  end

  private

    def set_order_status
      self.order_status = OrderStatus.find_by(name: "In progress")
    end

    def update_subtotal
      self[:subtotal] = subtotal
    end
end
