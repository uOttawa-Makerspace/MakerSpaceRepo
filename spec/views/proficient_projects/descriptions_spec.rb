# frozen_string_literal: true

require "rails_helper"

# Proficient project descriptions are sanitised like other rich text
# (Rails' default sanitize allowlist, as used across the app's views).
RSpec.describe "Proficient project description rendering", type: :view do
  def render_preview(description)
    stub_template "action_view/test_case/test/_proficient_project_row.html.erb" => ""
    project = build_stubbed(:proficient_project, description: description)
    render partial: "proficient_projects/preview",
           locals: { proficient_project: project, order_item: nil, user_order_items: nil }
    rendered
  end

  it "drops scripts, event-handler attributes and javascript: links" do
    html = render_preview(
      '<p>Hi</p><script>alert(1)</script><img src="/a.png" onerror="alert(2)">' \
      '<a href="javascript:alert(3)">click</a>'
    )
    expect(html).to include("<p>Hi</p>")
    expect(html).not_to include("<script")
    expect(html).not_to include("onerror")
    expect(html).not_to include("javascript:")
  end

  it "keeps normal formatting: bold, lists, links and images" do
    html = render_preview(
      '<h1>Title</h1><strong>bold</strong><ul><li>one</li></ul>' \
      '<a href="https://example.com/x">link</a><img src="https://example.com/i.png" alt="pic">'
    )
    expect(html).to include("<h1>Title</h1>", "<strong>bold</strong>", "<ul><li>one</li></ul>")
    expect(html).to include('<a href="https://example.com/x">link</a>')
    expect(html).to match(%r{<img [^>]*src="https://example.com/i.png"})
  end
end
