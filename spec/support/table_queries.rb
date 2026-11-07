# frozen_string_literal: true

# Counts the SELECT statements a block runs against the given tables, so a request spec can
# assert that a page reads them in a number of queries that does not grow with its rows.
module TableQueries
  def selects_on(*tables)
    pattern = /\ASELECT .*FROM "?(#{tables.map { |t| Regexp.escape(t) }.join("|")})"?[ )]/m
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end
end

RSpec.configure { |config| config.include TableQueries, type: :request }
