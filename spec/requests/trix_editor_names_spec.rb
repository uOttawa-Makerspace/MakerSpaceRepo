# frozen_string_literal: true

require "rails_helper"

# A <trix-editor> is not a labelable element, so a label's `for` never names it:
# each editor is named through aria-labelledby (pointing at its visible label)
# or aria-label.
RSpec.describe "Rich text editor names", type: :request do
  let(:admin) { create(:user, :admin, booking_approval: true) }

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  def editors_on(path, count)
    get path
    expect(response).to have_http_status(:ok), path
    expect(Nokogiri::HTML(response.body).css("trix-editor").size).to eq(count), path
    expect(unnamed_editors(response.body)).to be_empty, path
  end

  before { log_in!(admin) }

  it "names the editors of the admin forms" do
    JobOrderMessage.create!(name: "processed", message: "Done")
    editors_on(new_admin_job_type_path, 1)
    editors_on(edit_admin_job_type_path(create(:job_type)), 1)
    editors_on(new_admin_key_path, 1)
    editors_on(edit_admin_key_path(create(:key, space: create(:space))), 1)
    editors_on(new_admin_contact_info_path, 4)
    editors_on(edit_admin_contact_info_path(create(:contact_info)), 4)
    editors_on(admin_settings_path, 2)
  end

  it "names the editors of the FAQ, printer issue and project forms" do
    editors_on(new_faq_path, 2)
    editors_on(edit_faq_path(create(:faq)), 2)
    editors_on(new_printer_issue_path, 1)
    editors_on(new_proficient_project_path, 1)
    editors_on(edit_proficient_project_path(create(:proficient_project)), 1)
    editors_on(new_learning_area_path, 1)
    editors_on(new_project_proposal_path, 5)
    editors_on(new_repository_path(user_username: admin.username), 1)
  end

  it "names the editors of the staff printer updates and the order item modals" do
    editors_on(staff_printers_updates_printers_path, 1)
    order_item = create(:order_item)
    editors_on(order_item_approve_order_item_modal_path(order_item), 1)
    editors_on(order_item_revoke_order_item_modal_path(order_item), 1)
  end

  it "names an editor by the label the builder gives it" do
    get new_faq_path
    doc = Nokogiri::HTML(response.body)
    editor = doc.at_css("trix-editor#faq_body_en")
    expect(editor["aria-labelledby"]).to eq("faq_body_en_label")
    expect(doc.at_css("label#faq_body_en_label")["for"]).to eq("faq_body_en")
  end

  it "keeps an explicit name instead of pointing at a label" do
    JobOrderMessage.create!(name: "processed", message: "Done")
    get admin_settings_path
    editor = Nokogiri::HTML(response.body).css("trix-editor").first
    expect(editor["aria-label"]).to eq("Job order processed default email")
    expect(editor["aria-labelledby"]).to be_nil
  end
end
