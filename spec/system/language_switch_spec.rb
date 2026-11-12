# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The language switch in the header", type: :system, skip_bullet: true do
  let(:user) { create(:user, :regular_user) }

  before do
    stub_request(:get, %r{\Ahttps://simpli\.events/api/organizer/}).to_return(status: 200, body: { events: [] }.to_json)
  end

  it "switches the page to French, saves it for a signed-in user and stays on the page" do
    log_in_as(user, to: tos_path)
    click_button I18n.t("name", locale: :fr)

    expect(page).to have_css("html[lang='fr']")
    expect(page).to have_current_path(tos_path)
    expect(user.reload.locale).to eq("fr")
  end
end
