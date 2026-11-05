# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/key_requests.js on the key request
# form and wizard (steps are saved with PATCH). Real login, real page JS.
RSpec.describe "Key request form and wizard", type: :system, skip_bullet: true do
  let(:user) { create(:user, :staff, name: "Wanda Wizard") }
  let!(:space) { create(:space, name: "Machine Shop", keycode: "MS-1") }
  let!(:other_space) { create(:space, name: "Wood Shop", keycode: "WS-2") }
  let!(:supervisor) { create(:user, :admin, name: "Sam Supervisor") }

  def pick(id, text, search: nil)
    native = find("##{id}", visible: :all)
    expect(native[:class].to_s.split).to include("tomselected")
    wrapper = native.find(:xpath, "following-sibling::div[contains(@class,'ts-wrapper')][1]")
    wrapper.find(".ts-control").click
    wrapper.find(".ts-control input").send_keys(search) if search
    wrapper.find(".ts-dropdown .option", text: text).click
    page.execute_script("arguments[0].tomselect.close()", native)
  end

  def fill_personal_details
    fill_in "key_request_student_number", with: "300123456"
    fill_in "key_request_phone_number", with: "6135550101"
    fill_in "key_request_emergency_contact", with: "Mum"
    fill_in "key_request_emergency_contact_phone_number", with: "6135550102"
  end

  before { log_in_as(user) }

  describe "new request" do
    before do
      visit new_key_request_path
      expect(page).to have_css("#space-select.tomselected", visible: :all)
      expect(page).to have_css("#supervisor-select.tomselected", visible: :all)
    end

    it "turns the department and supervisor lists into searchable lists" do
      expect(page).to have_css("#space-select + .ts-wrapper")
      expect(page).to have_css("#supervisor-select + .ts-wrapper")
    end

    it "saves the picked department and supervisor and opens step 2 of the wizard" do
      fill_personal_details
      # the supervisor list is picked first: an open department list would cover it
      pick "supervisor-select", "Sam Supervisor", search: "Sam"
      pick "space-select", "Wood Shop", search: "Wood"
      click_button "Next Step"

      expect(page).to have_text("Lab")
      request = KeyRequest.find_by(user_id: user.id)
      expect(request).to have_attributes(space_id: other_space.id, supervisor_id: supervisor.id, status: "in_progress",
                                         student_number: "300123456")
      expect(page).to have_current_path(key_request_steps_path(key_request_id: request.id, step: 2))
    end
  end

  describe "editing step 1 of the wizard" do
    let!(:request) do
      create(:key_request, :status_in_progress, user: user, space: space, supervisor: supervisor)
    end

    it "saves the changed department with PATCH and shows step 2" do
      visit key_request_steps_path(key_request_id: request.id, step: 1)
      expect(page).to have_css("#space-select.tomselected", visible: :all)
      pick "space-select", "Wood Shop", search: "Wood"
      click_button "Next Step"

      wait_until("department not saved") { request.reload.space_id == other_space.id }
      expect(request.reload.supervisor_id).to eq(supervisor.id)
      expect(page).to have_current_path(key_request_steps_path(key_request_id: request.id), ignore_query: true)
    end

    it "enhances the lists when step 1 is reached by a link from the request page" do
      visit key_request_path(request)
      wait_for_app_js
      click_link "Edit Request"
      expect(page).to have_current_path(key_request_steps_path(key_request_id: request.id, step: 1))
      expect(page).to have_css("#space-select.tomselected", visible: :all)
    end
  end
end
