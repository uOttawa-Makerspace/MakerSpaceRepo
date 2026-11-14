# frozen_string_literal: true

# Finds the translation keys that app code names literally: t("a.b"), I18n.t(:"a.b"), a lazy t(".c")
# in a view (resolved to the view's path, the way ActionView resolves it) and
# Model.human_attribute_name(:attr). A key built at runtime (an interpolated string or a variable)
# cannot be read from the source; those calls are collected as skipped instead.
module TranslationKeyScan
  # Every app directory but javascript (which reads no locale data) and assets.
  DIRECTORIES = %w[
    channels components controllers helpers jobs mailers models serializers services validator validators views
  ].freeze
  SOURCES = "app/{#{DIRECTORIES.join(',')}}/**/*.{rb,erb}".freeze

  QUOTED = /"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/

  # t(...) / I18n.t(...) with the first argument, or t "..." without parentheses.
  CALL = /(?:\bI18n\.|(?<![\w.@:]))t(?:\(\s*(?<arg>:?#{QUOTED}|[^\s,)]+)|\s+(?<arg>:?#{QUOTED}))/

  HUMAN_ATTRIBUTE = /(?:(?<receiver>[\w:.]+)\.)?\bhuman_attribute_name\(\s*(?<arg>:\w+|#{QUOTED}|[^\s,)]+)/

  # English humanizes an attribute name it has no translation for, so only French must define one.
  Found = Data.define(:key, :location, :locales)
  Skipped = Data.define(:call, :location)

  # [found keys, skipped calls] across every source file.
  def self.scan(root = Rails.root)
    root.glob(SOURCES).sort.each_with_object([[], []]) do |path, (found, skipped)|
      file = path.relative_path_from(root).to_s
      source = strip_comments(path.read)
      calls(source, file).each { |item| (item.is_a?(Found) ? found : skipped) << item }
    end
  end

  def self.calls(source, file)
    each_match(source, CALL).map { |match, line| translation(match, file, line) } +
      each_match(source, HUMAN_ATTRIBUTE).map { |match, line| attribute(match, file, line) }
  end

  def self.each_match(source, pattern)
    source.to_enum(:scan, pattern).map { [Regexp.last_match, source[0...Regexp.last_match.begin(0)].count("\n") + 1] }
  end

  def self.translation(match, file, line)
    location = "#{file}:#{line}"
    key = literal(match[:arg])
    return Skipped.new(match[0], location) if key.nil? || (key.start_with?(".") && !file.start_with?("app/views/"))

    Found.new(key.start_with?(".") ? lazy_scope(file) + key : key, location, %i[en fr])
  end

  def self.attribute(match, file, line)
    location = "#{file}:#{line}"
    name = literal(match[:arg])
    model = (match[:receiver] || model_class_name(file))&.safe_constantize
    return Skipped.new(match[0], location) unless name && model.respond_to?(:model_name)

    Found.new("activerecord.attributes.#{model.model_name.i18n_key}.#{name}", location, %i[fr])
  end

  # The key inside a quoted string or symbol, or nil when it is built at runtime.
  def self.literal(arg)
    text = arg.delete_prefix(":")
    return text if arg.start_with?(":") && text.match?(/\A\w+\z/)
    return unless text.match?(/\A#{QUOTED}\z/o)

    body = text[1...-1]
    body unless text.start_with?('"') && body.include?('#{')
  end

  # app/views/users/tabs/_home.html.erb -> "users.tabs.home"
  def self.lazy_scope(file)
    file.delete_prefix("app/views/").sub(/\..*\z/, "").gsub(%r{/_?}, ".")
  end

  def self.model_class_name(file)
    file.match(%r{\Aapp/models/(?!concerns/)(.+)\.rb\z}) { |m| m[1].camelize }
  end

  # ERB comments and whole-line Ruby comments.
  def self.strip_comments(source)
    source.gsub(/<%#.*?%>/m) { |c| "\n" * c.count("\n") }.gsub(/^[ \t]*#(?!\{).*$/, "")
  end
end
