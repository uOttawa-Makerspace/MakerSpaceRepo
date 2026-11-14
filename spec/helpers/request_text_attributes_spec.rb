# frozen_string_literal: true

require "rails_helper"

# The texts the page's JavaScript shows when a request fails (src/request_error.js), and the texts of the page
# widgets (src/page_locale.js), rendered on the <html> element.
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

  it "renders the widget texts as one JSON attribute, worded in the page's language" do
    texts = %i[en fr].index_with do |locale|
      html = I18n.with_locale(locale) { helper.tag.div(**helper.request_text_attributes) }
      JSON.parse(Nokogiri::HTML5.fragment(html).at("div")["data-widget-texts"])
    end

    expect(texts[:en].dig("datatables", "search")).to eq("Search:")
    expect(texts[:en].dig("datatables", "entries")).to eq("_" => "entries", "1" => "entry")
    expect(texts[:en].dig("tom_select", "no_results")).to eq("No results found")
    expect(texts[:en].dig("flatpickr", "date_time")).to eq("F j, Y at H:i")
    expect(texts[:fr].dig("datatables", "search")).to eq("Rechercher :")
    expect(texts[:fr].dig("tom_select", "no_results")).to eq("Aucun résultat")
    expect(texts[:fr].dig("flatpickr", "date")).to eq("J F Y")
  end
end
