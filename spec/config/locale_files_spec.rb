# frozen_string_literal: true

require "rails_helper"

# Every locale file under config/locales, read the way Rails reads them: all files are merged
# per locale. English and French must describe the same keys, no value may be blank, and a key
# must have one definition (a second definition in another file, or twice in one file, silently
# wins or loses depending on load order).
RSpec.describe "Locale files" do
  # Namespaces whose other-language half is supplied by a gem (rails-i18n style defaults and
  # will_paginate's own en file), so config/locales legitimately carries only one language.
  let(:library_namespaces) { %w[date time datetime number errors helpers support will_paginate] }
  let(:files) { Rails.root.glob("config/locales/**/*.yml").sort }

  # { "en" => { "key.path" => { "file.yml" => value } } }
  let(:definitions) do
    files.each_with_object(Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }) do |file, defs|
      (YAML.load_file(file, aliases: true) || {}).each do |locale, tree|
        flatten(tree).each { |key, value| defs[locale.to_s][key][file.basename.to_s] = value }
      end
    end
  end

  def flatten(hash, prefix = nil, out = {})
    hash.each do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flatten(value, path, out) : out[path] = value
    end
    out
  end

  def translated_keys(locale)
    definitions.fetch(locale).keys.reject { |key| library_namespaces.include?(key.split(".").first) }
  end

  it "has an English and a French locale, and no other" do
    expect(definitions.keys).to contain_exactly("en", "fr")
  end

  it "defines the same keys in English and French" do
    en = translated_keys("en")
    fr = translated_keys("fr")

    expect(en - fr).to be_empty, "missing in French:\n#{(en - fr).join("\n")}"
    expect(fr - en).to be_empty, "missing in English:\n#{(fr - en).join("\n")}"
  end

  it "has no blank value in any locale" do
    blank = definitions.flat_map do |locale, keys|
      keys.flat_map { |key, by_file| by_file.select { |_, v| v.nil? || v.to_s.strip.empty? }.keys.map { |f| "#{locale} #{key} (#{f})" } }
    end

    expect(blank).to be_empty, "blank values:\n#{blank.join("\n")}"
  end

  it "keeps one text per key: no key is defined twice with different text" do
    conflicts = definitions.flat_map do |locale, keys|
      keys.filter_map do |key, by_file|
        next if by_file.values.uniq.size <= 1

        "#{locale} #{key}: #{by_file.map { |f, v| "#{f}=#{v.inspect}" }.join(' | ')}"
      end
    end

    expect(conflicts).to be_empty, "conflicting definitions:\n#{conflicts.join("\n")}"
  end

  it "defines a key in only one file" do
    repeated = definitions.flat_map do |locale, keys|
      keys.filter_map { |key, by_file| "#{locale} #{key}: #{by_file.keys.join(', ')}" if by_file.size > 1 }
    end

    expect(repeated).to be_empty, "defined in several files:\n#{repeated.join("\n")}"
  end

  it "has no mapping key repeated inside one file (the later one silently replaces the earlier)" do
    repeated = files.flat_map do |file|
      duplicates = []
      walk = lambda do |node, path|
        next unless node.is_a?(Psych::Nodes::Mapping)

        keys = node.children.each_slice(2).map { |k, _| k.value }
        keys.tally.each { |k, n| duplicates << "#{file.basename}: #{(path + [k]).join('.')}" if n > 1 }
        node.children.each_slice(2) { |k, v| walk.call(v, path + [k.value]) }
      end
      document = Psych.parse_file(file.to_s)
      walk.call(document.children.first, []) if document
      duplicates
    end

    expect(repeated).to be_empty, "repeated mapping keys:\n#{repeated.join("\n")}"
  end
end
