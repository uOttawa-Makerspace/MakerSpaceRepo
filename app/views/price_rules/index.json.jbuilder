# frozen_string_literal: true

json.array! @price_rules, partial: 'price_rules/price_rule', as: :price_rule
