# frozen_string_literal: true

require "rails_helper"

# The new/edit form behaviours must work however the page is reached, including
# a Turbo visit from the learning area index, which loads the same script.
RSpec.describe "Learning module form", type: :system do
  let(:admin) { create(:user, :admin) }
  let!(:training) { create(:training, name_en: "Laser Cutting EN") }

  def turbo_visit(path)
    page.execute_script("Turbo.visit(arguments[0])", path)
  end

  def open_new_form_through_turbo
    log_in_as(admin, to: learning_area_index_path)
    expect(page).to have_link("New learning module")
    turbo_visit(new_learning_area_path)
    expect(page).to have_css("h1", text: "New Learning Module")
  end

  it "asks for an image when the new form is reached through a Turbo visit" do
    open_new_form_through_turbo
    fill_in "repository_title", with: "Turbo module"
    click_button "Create Learning Module"

    expect(page).to have_css(".invalid-feedback", text: "You must upload at least one image")
    expect(page).to have_current_path(new_learning_area_path)
    expect(LearningModule.where(title: "Turbo module")).to be_empty
  end

  it "adds another photo input when the new form is reached through a Turbo visit" do
    open_new_form_through_turbo
    expect(page).to have_css("input[type=file].image-upload", count: 1)

    find("#new-photo-input").click
    expect(page).to have_css("input[type=file].image-upload", count: 2)
  end

  it "asks for an image when the new form is loaded directly" do
    log_in_as(admin, to: new_learning_area_path)
    fill_in "repository_title", with: "Direct module"
    click_button "Create Learning Module"
    expect(page).to have_css(".invalid-feedback", text: "You must upload at least one image")
  end

  it "switches between SCORM and regular file fields on a module edit reached through a Turbo visit" do
    learning_module = create(:learning_module, training: training)
    log_in_as(admin, to: learning_area_index_path)
    turbo_visit(edit_learning_area_path(learning_module.id))
    expect(page).to have_css("h1", text: "Edit Learning Module")

    expect(page).to have_css("#regular-files-section")
    expect(page).to have_no_css("#scorm-section")
    check "SCORM package"
    expect(page).to have_css("#scorm-section")
    expect(page).to have_no_css("#regular-files-section")
  end
end
