class Membership < ApplicationRecord
  include ShopifyConcern
  
  belongs_to :user
  
  attribute :status, :string, default: 'paid'

  enum status: {
    pending: 'pending',
    paid: 'paid',
    failed: 'failed'
  }, _default: 'pending'

  MEMBERSHIP_TYPES = {
    '1_day' => { duration: 1.day, price: 10.00, title: '1 Day Membership' },
    '1_month' => { duration: 1.month, price: 30.00, title: '1 Month Membership' },
    '1_semester' => { duration: 4.months, price: 100.00, title: '1 Semester Membership' }
  }.freeze
  
  validates :membership_type, inclusion: { in: MEMBERSHIP_TYPES.keys }
  
  before_create :set_dates

  scope :active, -> {
    where('end_date > ?', Time.current)
      .where(status: :paid)
      .order(end_date: :desc)
  }

  def shopify_draft_order_key_name
    "membership"
  end

  def shopify_draft_order_line_items
    [{
      originalUnitPrice: price.to_s,
      quantity: 1,
      title: membership_title,
      requiresShipping: false,
      taxable: false
    }]
  end

  def checkout_link
    shopify_draft_order['invoiceUrl']
  end

  def price
    MEMBERSHIP_TYPES[membership_type][:price]
  end

  def membership_title
    MEMBERSHIP_TYPES[membership_type][:title]
  end

  def duration
    MEMBERSHIP_TYPES[membership_type][:duration]
  end

  def active?
    end_date > Time.current && status == 'paid'
  end

  def self.calculate_end_date(user)
    last_active = user.memberships.where('end_date > ?', Time.current).order(end_date: :desc).first
    last_active ? last_active.end_date : Time.current
  end

  private

  def set_dates
    self.start_date = Time.current
    self.end_date = Membership.calculate_end_date(user) + duration
  end
end