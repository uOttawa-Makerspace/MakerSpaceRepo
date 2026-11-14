# frozen_string_literal: true

require "rails_helper"
require "i18n/tasks"

# Every translation key the app uses exists in English and French, and every English key has a
# French twin (i18n-tasks, configured in config/i18n-tasks.yml). Production falls back to English
# when a French key is missing, so a missing key would show English to a French reader instead of
# failing; this catches it before any page is rendered. Keys built at runtime ("a.#{b}") cannot be
# checked statically. Unused keys are reported by `bundle exec i18n-tasks unused`, not checked here.
RSpec.describe "Translation keys used by the app" do
  # Keys used today but defined in neither locale ("all"). Take a key off once it is defined, or its
  # use is fixed; never add one.
  known_missing = %w[
    all:job_orders.order.unnamed_task
    all:settings.admin.title
    all:users.tablist..about
  ]

  before(:context) do
    leaves = I18n::Tasks::BaseTask.new.missing_keys.leaves
    @missing = leaves.map { |leaf| "#{leaf.data[:locale] || 'all'}:#{leaf.full_key(root: false)}" }.uniq
  end

  it "defines every key the app uses in English and French" do
    new_missing = @missing - known_missing

    expect(new_missing).to be_empty,
                           "missing translations (run `bundle exec i18n-tasks missing`):\n#{new_missing.join("\n")}"
  end

  it "lists only keys that are still missing" do
    expect(known_missing - @missing).to eq([])
  end

  # i18n-tasks does not read human_attribute_name. English humanizes an attribute it has no name for,
  # so only French must define one. A call whose model or attribute is a variable cannot be checked.
  it "names in French every attribute the app passes literally to human_attribute_name" do
    calls = Rails.root.glob("app/**/*.{rb,erb}").flat_map do |path|
      model = path.to_s[%r{/app/models/(?!concerns/)(.+)\.rb\z}, 1]&.camelize
      literal_calls = path.read.scan(/(?:([A-Z][\w:]*)\.)?\bhuman_attribute_name\(\s*:(\w+)/)
      literal_calls.map { |klass, attr| [klass || model, attr] }
    end
    unnamed = calls.filter_map do |klass, attr|
      key = "activerecord.attributes.#{klass&.safe_constantize&.model_name&.i18n_key}.#{attr}"
      key unless I18n.exists?(key, :fr)
    end

    expect(calls).not_to be_empty
    expect(unnamed).to eq([])
  end
end
