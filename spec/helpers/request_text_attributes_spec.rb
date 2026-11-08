# frozen_string_literal: true

require "rails_helper"

# The texts the page's JavaScript shows when a request fails (src/request_error.js), rendered on the <html> element.
RSpec.describe ApplicationHelper, "#request_text_attributes" do
  it "renders the translated texts as data attributes in English" do
    html = I18n.with_locale(:en) { helper.tag.html(**helper.request_text_attributes) }

    expect(html).to include(%(data-request-failed="#{I18n.t("errors.generic.request_failed", locale: :en)}"))
    expect(html).to include("data-request-network=")
    expect(html).to include("data-request-copy-failed=")
  end

  it "renders them in French" do
    attributes = I18n.with_locale(:fr) { helper.request_text_attributes }

    expect(attributes[:data][:request_failed]).to eq(I18n.t("errors.generic.request_failed", locale: :fr))
    expect(attributes[:data][:request_failed]).not_to eq(I18n.t("errors.generic.request_failed", locale: :en))
  end
end
