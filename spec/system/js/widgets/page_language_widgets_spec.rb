# frozen_string_literal: true

require "rails_helper"

# The page widgets take their texts from the page's language (src/page_locale.js
# reads the texts the layout renders on <html>): here the trainings table, a DataTable.
RSpec.describe "Widgets in the page's language", type: :system do
  let(:admin) { create(:user, :admin) }

  before { create(:training) }

  it "words the trainings table in French on a French page", js: true do
    log_in_as(admin, to: admin_trainings_path(locale: :fr))

    expect(page).to have_css(".dt-search label", text: "Rechercher :")
    expect(page).to have_css(".dt-info", text: "Affichage de 1 à 1 sur 1 entrée")
  end

  it "keeps the library's English on an English page", js: true do
    log_in_as(admin, to: admin_trainings_path)

    expect(page).to have_css(".dt-search label", text: "Search:")
    expect(page).to have_css(".dt-info", text: "Showing 1 to 1 of 1 entry")
  end
end
