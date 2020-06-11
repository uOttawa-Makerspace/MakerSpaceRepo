# frozen_string_literal: true

json.extract! price_rule, :id, :created_at, :updated_at
json.url price_rule_url(price_rule, format: :json)
