class Membership < ApplicationRecord
  include ShopifyConcern

  belongs_to :user
  belongs_to :membership_tier

  attribute :status, :string, default: 'paid'

  enum :status, {
         pending: 'pending',
         paid: 'paid',
         failed: 'failed',
         revoked: 'revoked'
       },
       default: 'pending'

  before_create :set_dates

  scope :active, -> { where('end_date > ?', Time.current).where(status: :paid).order(end_date: :desc) }

  delegate :duration, to: :membership_tier

  def shopify_draft_order_key_name
    'membership'
  end

  def shopify_draft_order_line_items
    [{ originalUnitPrice: membership_tier.price(user).to_s, quantity: 1, title: membership_title }]
  end

  def checkout_link
    # Special case to prevent people from triggering shopify calls for a faculty membership
    if membership_tier.title_en.downcase.include?('faculty')
      flash[:notice] = "Money can buy a lot of things, but not this one."
      return '/'
    end
    shopify_draft_order['invoiceUrl']
  end

  def membership_title
    membership_tier.title(I18n.locale)
  end

  def active?
    end_date > Time.current && status == 'paid'
  end

  def self.calculate_end_date(user)
    last_active =
      user
        .memberships
        .where('end_date > ?', Time.current)
        .order(end_date: :desc)
        .first
    last_active ? last_active.end_date : Time.current
  end

  private

  def set_dates
    self.start_date ||= Membership.calculate_end_date(user)
    self.end_date ||= Membership.calculate_end_date(user) + duration
  end
end
