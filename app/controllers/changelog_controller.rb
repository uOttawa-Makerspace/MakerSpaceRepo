class ChangelogController < ApplicationController
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

      @changelog_html = markdown.render(raw_markdown).html_safe
    else
      @changelog_html = "<p>No changelog available.</p>".html_safe
    end
  end
end