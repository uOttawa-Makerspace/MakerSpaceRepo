# frozen_string_literal: true

require "rails_helper"

# Every translation key that app code names literally exists in English and French. Production
# falls back to English when a French key is missing, so a missing key would show English to a
# French reader instead of failing; this catches it before any page is rendered.
# Keys built at runtime cannot be checked here: they are listed with SKIPPED=1.
RSpec.describe "Translation keys used by the app" do
  found, skipped = TranslationKeyScan.scan

  # Keys used with an English default: until they are defined, French readers see that English.
  # Take a key off once it is defined in both locales; never add one.
  known_missing = %w[
    en:job_orders.order.unnamed_task fr:job_orders.order.unnamed_task
    en:settings.admin.title fr:settings.admin.title
  ]

  it "finds the keys the app uses" do
    expect(found.size).to be > 1000
  end

  missing = found.flat_map do |use|
    absent = use.locales.reject { |locale| I18n.exists?(use.key, locale) }
    absent.map { |locale| ["#{locale}:#{use.key}", use.location] }
  end

  it "defines every literal key in English and French" do
    new_missing = missing.reject { |key, _| known_missing.include?(key) }.map { |key, location| "#{key} (#{location})" }

    expect(new_missing).to be_empty, "missing translations:\n#{new_missing.uniq.join("\n")}"
  end

  it "lists only keys that are still missing" do
    expect(known_missing - missing.map(&:first)).to eq([])
  end

  it "lists the calls whose key is built at runtime", if: ENV["SKIPPED"] do
    lines = skipped.map { |call| "  #{call.location}  #{call.call}" }
    RSpec.configuration.reporter.message("\n#{skipped.size} translation calls with a runtime key:\n#{lines.join("\n")}")
  end
end
