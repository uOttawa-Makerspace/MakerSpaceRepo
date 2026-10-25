# frozen_string_literal: true

require "rails_helper"

# End-to-end key journey: a staff member fills the multi-step access key form,
# submits it, an admin approves it from the key requests admin page, and the
# requester sees the approved status.
RSpec.describe "Journey: key request", type: :system do
  let!(:space) { create(:space, name: "Key Space") }
  let!(:requester) { create(:user, :staff) }
  let!(:admin) { create(:user, :admin, name: "Alex Admin") }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
    ActionMailer::Base.deliveries.clear
  end

  it "request through the wizard -> admin approves -> requester sees approved" do
    as_actor(:requester) do
      log_in_as(requester)
      visit new_key_request_path
      expect(page).to have_text("Access Key Form - Personal Information")
      fill_in "key_request_student_number", with: "300123456"
      fill_in "key_request_phone_number", with: "613-555-0100"
      fill_in "key_request_emergency_contact", with: "Pat Parent"
      fill_in "key_request_emergency_contact_phone_number", with: "613-555-0199"
      select "Key Space", from: "space-select"
      select "Alex Admin", from: "supervisor-select"
      click_button "Next Step"

      expect(page).to have_text("General laboratory rules")
      choose "key_request_read_lab_rules_true"
      click_button "Next Step"

      expect(page).to have_text("Safety questionnaire")
      all("input[id^='key_request_question_']").each_with_index { |el, i| el.set("answer #{i + 1}") }
      click_button "Next Step"

      expect(page).to have_css("#key_request_read_policies_true")
      choose "key_request_read_policies_true"
      click_button "Next Step"

      expect(page).to have_css("#key_request_read_agreement_true")
      choose "key_request_read_agreement_true"
      click_button "Submit Form"

      expect(page).to have_text("You have successfully submitted the key request form")
      expect(page).to have_text("Waiting for approval")
    end
    key_request = KeyRequest.find_by!(user: requester)
    expect(key_request.status).to eq("waiting_for_approval")
    expect(key_request.space).to eq(space)
    expect(key_request.supervisor).to eq(admin)

    as_actor(:admin) do
      log_in_as(admin)
      visit requests_admin_keys_path
      expect(page).to have_css("h2", text: "Key Requests")
      click_button "Waiting for Approval" # accordion
      expect(page).to have_css("#collapseOne.show")
      click_button "Approve"
      expect(page).to have_text("Successfully approved key request.")
    end
    expect(key_request.reload.status).to eq("approved")

    as_actor(:requester) do
      visit key_request_path(key_request)
      expect(page).to have_css(".badge", text: "Approved")
    end
  end
end
