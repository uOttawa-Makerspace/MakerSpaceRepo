# Stores admin configuration for lockers. Right now it's just the link to the
# locker product on shopify, but later on we'll have lockers for different
# semesters.
class LockerOption < ApplicationRecord
  validates :name, uniqueness: true, presence: true
  normalizes :name, with: ->(name) { name.strip.downcase }

  LOCKER_PRODUCT_LINK = 'locker_product_link'.freeze
  LOCKERS_ENABLED = 'lockers_enabled'.freeze

  validates :value,
            format: {
              with: %r{gid://shopify/Product/[0-9]+}
            },
            if: -> { name == LOCKER_PRODUCT_LINK }

  # Store the main product GID for a shopify product. This used to be a public
  # facing link, but we delisted the locker product and now can't access without
  # admin auth.
  def self.locker_product_link=(link)
    find_or_create_by(name: LOCKER_PRODUCT_LINK).update(value: link)
  end

  def self.locker_product_link
    find_or_create_by(name: LOCKER_PRODUCT_LINK).value
  end

  # Returns the price plus some extra data for views
  def self.locker_product_info
    return unless locker_product_link

    product = ShopifyService.product(locker_product_link)

    {
      title: product['title'],
      status: product['status'],
      updated_at: product['updated_at'],
      id: product['id'],
      image: product['media']['nodes'].first&.dig('preview', 'image', 'url'),
      variants:
        product['variants']['nodes'].each_with_object({}) do |node, memo|
          memo[node['id']] = {
            id: node['id'],
            displayName: node['displayName'],
            price: node['price'],
            sku: node['sku'],
            image: node['media']['nodes'].first&.dig('preview', 'url')
          }
        end
    }
    # rescue StandardError => e
    #   Rails.logger.fatal e
    #   nil
  end

  def self.locker_product_variant_id
    locker_product_info[:variant_id]
  rescue StandardError => e
    Rails.logger.fatal e
    nil
  end

  def self.locker_rental_price
    locker_product_info[:price]
  rescue StandardError => e
    Rails.logger.warn e
    0
  end

  # Sitewide locker disable switch
  def self.lockers_enabled=(enabled)
    # HACK: force bool
    if enabled
      find_or_create_by(name: LOCKERS_ENABLED).update(value: 't')
    else
      find_or_create_by(name: LOCKERS_ENABLED).update(value: 'f')
    end
  end

  def self.lockers_enabled
    find_or_create_by(name: LOCKERS_ENABLED).value == 't'
  end
end
