# frozen_string_literal: true

require "rails_helper"

# Printer issue descriptions are sanitised like other rich text.
RSpec.describe MsrMailer, "#new_printer_issue", type: :mailer do
  def html_body(description)
    issue = create(:printer_issue, description: description)
    ActionMailer::Base.deliveries.clear
    MsrMailer.new_printer_issue(issue, "staff@example.com").deliver_now
    mail = ActionMailer::Base.deliveries.last
    (mail.html_part || mail).body.decoded
  end

  it "drops scripts, event-handler attributes and javascript: links" do
    body = html_body(
      '<p>Nozzle</p><script>alert(1)</script><img src="/a.png" onerror="alert(2)">' \
      '<a href="javascript:alert(3)">click</a>'
    )
    expect(body).to include("<p>Nozzle</p>")
    expect(body).not_to include("<script")
    expect(body).not_to include("onerror")
    expect(body).not_to include("javascript:")
  end

  it "keeps normal formatting" do
    body = html_body("<strong>Jammed</strong><ul><li>step one</li></ul>")
    expect(body).to include("<strong>Jammed</strong>")
    expect(body).to include("<ul><li>step one</li></ul>")
  end
end
