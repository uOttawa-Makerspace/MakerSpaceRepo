class ChangelogController < ApplicationController
  # The configured sanitizer's allow-list plus what the markdown renderer emits for tables and links
  TABLE_TAGS = %w[table thead tbody tr th td].freeze
  LINK_ATTRIBUTES = %w[target rel].freeze

  # Bump when the renderer options or the allow-list above change: cached HTML is keyed on it
  CACHE_VERSION = 1

  def index
    changelog_path = Rails.root.join("CHANGELOG.md")
    stat = File.stat(changelog_path)

    # Rendered and sanitized once per file version, not on every request
    html = Rails.cache.fetch(["changelog", CACHE_VERSION, stat.mtime.to_f, stat.size], expires_in: 1.day) do
      render_markdown(File.read(changelog_path))
    end
    @changelog_html = html.html_safe # sanitized in render_markdown
  rescue Errno::ENOENT
    @changelog_html = "<p>No changelog available.</p>".html_safe
  end

  private

  def render_markdown(raw_markdown)
    # Strip the #changelog marker the builder inserts
    raw_markdown = raw_markdown.gsub(/^#changelog\s*$/, "")

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )

    markdown = Redcarpet::Markdown.new(renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      no_intra_emphasis: true
    )

    sanitizer = Rails::HTML::Sanitizer.safe_list_sanitizer
    helpers.sanitize(
      markdown.render(raw_markdown),
      tags: sanitizer.allowed_tags.to_a + TABLE_TAGS,
      attributes: sanitizer.allowed_attributes.to_a + LINK_ATTRIBUTES
    ).then { |safe| String.new(safe) }
  end
end
