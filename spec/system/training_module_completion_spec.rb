# frozen_string_literal: true

require "rails_helper"

# DOM-level characterization of the learning-module journey: learning area index
# -> module page -> Start Module -> Mark Completed (plain link GETs, no JS
# needed), plus the admin Edit affordance and the guest redirect.
RSpec.describe "Training module completion", type: :system do
  let(:user) { create(:user, :regular_user) }
  let(:training) { create(:training, name_en: "Laser Cutting EN") }
  let!(:learning_module) { create(:learning_module, training: training, title: "Kerf basics", description: "<p>Learn about kerf</p>") }

  it "sends a guest to the login page" do
    visit learning_area_path(learning_module)
    expect(page).to have_current_path(%r{\A/login}, ignore_query: true)
    expect(page).to have_css("nav.navbar")
  end

  it "takes a learner from the index through Start Module to Mark Completed" do
    log_in_as(user)
    visit learning_area_index_path
    expect(page).to have_css("nav.navbar")
    expect(page).to have_content("Laser Cutting EN")
    expect(page).to have_css("h6", text: "Kerf basics")
    expect(page).to have_no_link("Edit")

    find("a[href='#{learning_area_path(learning_module.id)}']", match: :first).click
    expect(page).to have_current_path(learning_area_path(learning_module.id))
    expect(page).to have_css("h1", text: "Kerf basics")
    expect(page).to have_content("Learn about kerf")
    expect(page).to have_content("Ready to start?")
    expect(page).to have_no_link("Mark Completed")

    click_link "Start Module"
    expect(page).to have_current_path(learning_area_path(learning_module.id))
    expect(page).to have_content("You have successfully started the learning module !")
    expect(page).to have_content("In Progress")
    expect(page).to have_no_link("Start Module")
    expect(user.learning_module_tracks.last.status).to eq("in_progress")

    click_link "Mark Completed"
    expect(page).to have_content("You have successfully completed the learning module !")
    expect(page).to have_content("You've completed this module")
    expect(page).to have_no_link("Mark Completed")
    expect(page).to have_no_link("Start Module")
    expect(user.learning_module_tracks.last.status).to eq("completed")
  end

  it "shows the Edit link only to an admin" do
    admin = create(:user, :admin)
    log_in_as(admin)
    visit learning_area_path(learning_module.id)
    expect(page).to have_link("Edit", href: edit_learning_area_path(learning_module.id))
  end
end
