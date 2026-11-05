# frozen_string_literal: true

# Retired (chunk 20a removed the Shopify price rules / discount codes feature).
# The discount_codes table and its rows are kept. It has foreign keys to users
# and price_rules, and cc_moneys.discount_code_id points at it, so this bare
# record class exists ONLY so User#destroy can clear legacy rows and leave the
# cc_moneys that reference them intact. Do not add behavior here.
class DiscountCode < ApplicationRecord
  has_many :cc_moneys, dependent: :nullify
end
