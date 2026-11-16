# frozen_string_literal: true

require "rails_helper"

# The gallery rows and training requirement rows added on a proficient project
# form before leaving it are still on the page Turbo restores from its cache,
# and their remove buttons still remove them.
RSpec.describe "Rows added to a proficient project form, restored from the Turbo cache", type: :system,
                                                                                         skip_bullet: true do
  let(:admin) { create(:user, :admin) }

  def gallery_rows = ".input-group:has(> #new-photo-input) ~ .input-group"
  def requirement_rows = "#link-container > div"

  def expect_rows(gallery:, requirements:)
    expect(page).to have_css(gallery_rows, count: gallery)
    expect(page).to have_css(requirement_rows, count: requirements)
  end

  def add_rows_and_restore(path, requirements:)
    log_in_as(admin, to: path)
    wait_for_app_js
    2.times { click_button "new-photo-input" }
    click_button "New Requirement"
    expect_rows(gallery: 2, requirements: requirements + 1)
    leave_and_restore(path)
    expect_rows(gallery: 2, requirements: requirements + 1)
  end

  def expect_removable_rows(requirements:)
    first("#{gallery_rows} > .btn-danger").click
    all("#{requirement_rows} .tr-delete-button").last.click
    expect_rows(gallery: 1, requirements: requirements)
  end

  it "removes the rows added on the new form" do
    add_rows_and_restore(new_proficient_project_path, requirements: 0)
    expect_removable_rows(requirements: 0)
  end

  it "removes the rows added on the edit form, and its saved requirement rows" do
    project = create(:proficient_project)
    create(:training_requirement, proficient_project: project, level: "Beginner")
    add_rows_and_restore(edit_proficient_project_path(project), requirements: 1)
    expect_removable_rows(requirements: 1)
    find("#{requirement_rows} .tr-delete-button").click
    expect(page).to have_no_css(requirement_rows)
  end
end
