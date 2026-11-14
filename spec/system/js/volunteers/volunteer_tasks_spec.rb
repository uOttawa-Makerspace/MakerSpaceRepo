# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/volunteer_tasks.js: the card search on
# the task index and the image removal on the task edit form.
RSpec.describe "Volunteer task pages", type: :system, skip_bullet: true do
  # The page script runs again on turbo:load; a second run over the same page
  # must not bind its controls twice.
  def run_page_script_again
    page.execute_script('document.dispatchEvent(new Event("turbo:load"))')
  end

  describe "task index" do
    before do
      create(:volunteer_task, title: "Sweep the shop floor")
      create(:volunteer_task, title: "Paint the mural")
      log_in_as(create(:user, :volunteer_with_volunteer_program), to: volunteer_tasks_path)
      expect(page).to have_css(".task-item-card-col", count: 2)
      wait_for_app_js
    end

    it "shows only the cards that contain the searched text, also after the script runs again" do
      run_page_script_again
      fill_in "taskSearchInput", with: "MURAL"
      expect(page).to have_css(".task-item-card-col", text: "Paint the mural", count: 1)
      expect(page).to have_no_css(".task-item-card-col", text: "Sweep the shop floor")
      fill_in "taskSearchInput", with: ""
      expect(page).to have_css(".task-item-card-col", count: 2)
    end

    it "keeps one working picker per filter select on a page restored from the Turbo cache" do
      page.execute_script("Turbo.visit(#{volunteer_tasks_path(revisit: 1).to_json})")
      expect(page).to have_current_path(/revisit=1/)
      expect(page).to have_css(".task-item-card-col", count: 2)
      # Set only after the forward visit has loaded, so it marks the load of
      # the restored page; it runs after the page script's own handler.
      page.execute_script(<<~JS)
        document.addEventListener("turbo:load", () => {
          document.documentElement.dataset.restoredLoad = "done";
        }, { once: true });
      JS
      page.go_back
      expect(page).to have_css("html[data-restored-load='done']", visible: :all)

      %w[spaceFilter categoryFilter certFilter].each do |id|
        expect(page).to have_css("##{id} ~ .ts-wrapper", count: 1, visible: :all)
      end
      # the picker of a restored page can be reached with Tab, as on a fresh visit
      expect(page.evaluate_script("document.querySelector('#spaceFilter + .ts-wrapper .ts-control').tabIndex")).to eq(0)
      find("#categoryFilter + .ts-wrapper .ts-control").click
      find(".ts-dropdown .option", text: I18n.t("volunteer_area.tasks.categories.workshops")).click
      # both tasks are events, so a workshop filter hides them
      expect(page).to have_no_css(".task-item-card-col")
    end
  end

  describe "task edit form" do
    let(:task) { create(:volunteer_task) }

    before do
      create(:photo, volunteer_task: task)
      log_in_as(create(:user, :staff), to: edit_volunteer_task_path(task))
      expect(page).to have_css(".image-remove")
      wait_for_app_js
    end

    it "records a removed image's id once when the script has run again over the same page" do
      run_page_script_again
      find(".image-remove").click
      expect(page).to have_no_css(".image-remove")
      expect(find_by_id("deleteimages", visible: :hidden).value).to eq("#{task.photos.first.id},")
    end

    it "removes the whole image card, and the saved task no longer has the image" do
      expect(page).to have_css("#image-container .image-item img")
      find(".image-remove").click
      expect(page).to have_no_css("#image-container .image-item")
      expect(page).to have_no_css("#image-container img")
      find("#volunteerForm button[type=submit]").click
      expect(page).to have_current_path(volunteer_tasks_path)
      expect(task.reload.photos).to be_empty
    end
  end

  describe "task edit form with a photo whose file name contains a comma" do
    let(:task) { create(:volunteer_task) }
    let!(:kept) { create(:photo, volunteer_task: task) }
    let!(:comma) do
      png = Rails.root.join("spec/support/assets/avatar.png")
      create(:photo, volunteer_task: task, image: Rack::Test::UploadedFile.new(png, "image/png", original_filename: "before,after.png"))
    end

    it "removes that photo only, and keeps the other" do
      log_in_as(create(:user, :staff), to: edit_volunteer_task_path(task))
      expect(page).to have_css(".image-remove", count: 2)
      wait_for_app_js
      find(".image-remove[data-photo-id='#{comma.id}']").click
      expect(page).to have_css(".image-remove", count: 1)
      find("#volunteerForm button[type=submit]").click
      expect(page).to have_current_path(volunteer_tasks_path)
      expect(task.reload.photos).to contain_exactly(kept)
    end
  end
end
