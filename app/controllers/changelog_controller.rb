class ChangelogController < ApplicationController
  # The configured sanitizer's allow-list plus what the markdown renderer emits for tables and links
  TABLE_TAGS = %w[table thead tbody tr th td].freeze
  LINK_ATTRIBUTES = %w[target rel].freeze

  def index
    changelog_path = Rails.root.join("CHANGELOG.md")

    if File.exist?(changelog_path)
      # Rendered and sanitized once per file version, not on every request
      html = Rails.cache.fetch(["changelog", File.mtime(changelog_path).to_f, File.size(changelog_path)]) do
        render_markdown(File.read(changelog_path))
      end
      @changelog_html = html.html_safe # sanitized in render_markdown
    else
      @changelog_html = "<p>No changelog available.</p>".html_safe
    end
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
