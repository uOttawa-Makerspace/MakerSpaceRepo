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
  end

  describe "task edit form" do
    let(:task) { create(:volunteer_task) }

    before do
      create(:photo, volunteer_task: task)
      log_in_as(create(:user, :staff), to: edit_volunteer_task_path(task))
      expect(page).to have_css(".image-remove")
      wait_for_app_js
    end

    it "records a removed image once when the script has run again over the same page" do
      filename = task.photos.first.image.filename.to_s
      run_page_script_again
      find(".image-remove").click
      expect(page).to have_no_css(".image-remove")
      expect(find_by_id("deleteimages", visible: :hidden).value).to eq("#{filename},")
    end
  end
end
