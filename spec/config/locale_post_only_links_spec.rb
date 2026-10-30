# frozen_string_literal: true

require "rails_helper"

# A locale string must not hard-code a GET link to a route that only answers
# POST (a click would 404, or worse, it would be a state-changing GET again).
RSpec.describe "Locale strings and POST-only routes" do
  let(:post_only_paths) { %w[/development_programs/join_development_program /change_email] }

  it "no translation links to a POST-only path" do
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    strings = []
    walk = lambda do |value, key|
      case value
      when Hash then value.each { |k, v| walk.call(v, "#{key}.#{k}") }
      when String then strings << [key, value]
      end
    end
    I18n.backend.send(:translations).each { |locale, tree| walk.call(tree, locale.to_s) }

    offenders = strings.select { |_, v| post_only_paths.any? { |p| v.include?("href='#{p}'") || v.include?("href=\"#{p}\"") } }
    expect(offenders.map(&:first)).to eq([])
  end
end
