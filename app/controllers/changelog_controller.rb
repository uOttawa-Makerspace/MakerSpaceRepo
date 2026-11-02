class ChangelogController < ApplicationController
  # The default allow-list plus what the markdown renderer emits for tables and links
  TABLE_TAGS = %w[table thead tbody tr th td].freeze
  LINK_ATTRIBUTES = %w[target rel].freeze

  def index
    changelog_path = Rails.root.join("CHANGELOG.md")

    if File.exist?(changelog_path)
      raw_markdown = File.read(changelog_path)

      # Strip the #changelog marker the builder inserts
      raw_markdown.gsub!(/^#changelog\s*$/, "")

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

      @changelog_html = sanitize_html(markdown.render(raw_markdown))
    else
      @changelog_html = "<p>No changelog available.</p>".html_safe
    end
  end

  private

  def sanitize_html(html)
    sanitizer = Rails::HTML5::SafeListSanitizer
    helpers.sanitize(
      html,
      tags: sanitizer.allowed_tags.to_a + TABLE_TAGS,
      attributes: sanitizer.allowed_attributes.to_a + LINK_ATTRIBUTES
    )
  end
end