# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/src/file_upload.js on the project proposal form.
RSpec.describe "File upload fields", type: :system, skip_bullet: true do
  let(:image) { Rails.root.join("spec/support/assets/test.png") }

  before do
    log_in_as(create(:user, :regular_user), to: new_project_proposal_path)
    expect(page).to have_css("[data-file-upload-proposal-preview]")
    wait_for_app_js
  end

  it "previews a chosen gallery image with a named hidden field for it" do
    attach_file "project_proposal_photos", image
    within("[data-file-upload-proposal-preview]") do
      expect(page).to have_css(".file-upload-item-preview span", text: "test.png")
      expect(page).to have_css("input[type=file][name^='project_proposal[photos]']", visible: :hidden)
    end
  end

  it "leaves a field whose preview pane is missing a plain named file field" do
    page.execute_script(<<~JS)
      const input = document.createElement("input");
      input.type = "file";
      input.id = "unpreviewed_upload";
      input.name = "project_proposal[extra][]";
      input.dataset.fileUploadHelper = "";
      input.dataset.fileUploadPreviewSelector = "#no-such-pane";
      document.getElementById("project_proposal_photos").after(input);
      document.dispatchEvent(new Event("turbo:load"));
    JS
    expect(page).to have_css("#unpreviewed_upload[data-file-upload-initialized]")
    attach_file "unpreviewed_upload", image
    expect(find_by_id("unpreviewed_upload")["name"]).to eq("project_proposal[extra][]")
    expect(page.evaluate_script("document.getElementById('unpreviewed_upload').files.length")).to eq(1)
  end
end
