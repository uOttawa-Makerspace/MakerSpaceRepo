# Stores admin configuration for lockers. Right now it's just the link to the
# locker product on shopify, but later on we'll have lockers for different
# semesters.
class LockerOption < ApplicationRecord
  validates :name, uniqueness: true, presence: true
  normalizes :name, with: ->(name) { name.strip.downcase }

  LOCKER_PRODUCT_LINK = 'locker_product_link'.freeze

  # Store the product link for a shopify product. Note this is the public URL,
  # we then use the public json response to fetch the variant ID. Refer to
  # documentation for more information.
  def self.locker_product_link=(link)
    find_or_create_by(name: LOCKER_PRODUCT_LINK).update(value: link)
  end

  def self.locker_product_link
    find_or_create_by(name: LOCKER_PRODUCT_LINK).value
  end

  # Returns the price plus some extra data for views
  def self.locker_product_info
    return unless locker_product_link

    # Get public API response
    # Receive a product link, extract product variant ID using the public API
    shop_response = Excon.get("#{locker_product_link}.json")&.body
    return unless shop_response
    shop_json = JSON.parse(shop_response)

    product_json = shop_json['product']

    main_variant =
      shop_json['product']['variants'].find do |v|
        v['product_id'] == shop_json['product']['id']
      end

    return unless main_variant

    {
      title: product_json['title'],
      updated_at: product_json['updated_at'],
      product_id: main_variant['product_id'],
      variant_id: main_variant['id'],
      price: main_variant['price'],
      sku: main_variant['sku'],
      image_url: shop_json.dig('product', 'image', 'src')
    }
  rescue StandardError => e
    Rails.logger.fatal e
    nil
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
end
