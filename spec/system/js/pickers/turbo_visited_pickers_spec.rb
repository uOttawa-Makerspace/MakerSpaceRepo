# frozen_string_literal: true

require "rails_helper"

# Searchable pickers (TomSelect) on admin pages reached by a Turbo visit from
# another admin page: Turbo adds the page script to the head on that visit, and
# the script runs after the visit's turbo:load, so it must not wait for one.
RSpec.describe "Pickers on admin pages reached by a Turbo visit", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }

  def expect_picker_after_turbo_visit(path, id)
    log_in_as(admin, to: admin_users_path)
    wait_for_app_js
    page.execute_script("Turbo.visit(#{path.to_json})")
    expect(page).to have_current_path(path)
    expect(page).to have_css("##{id}.tomselected", visible: :all)
    expect(page).to have_no_css("##{id} + .ts-wrapper + .ts-wrapper", visible: :all)
  end

  it "sets up both skill pickers on the new training form" do
    expect_picker_after_turbo_visit(new_admin_training_path, "training_list_of_skills_en")
    expect(page).to have_css("#training_list_of_skills_fr.tomselected", visible: :all)
    expect(page).to have_no_css("#training_list_of_skills_fr + .ts-wrapper + .ts-wrapper", visible: :all)
  end

  it "sets up the job type picker on the new job option form" do
    create(:job_type)
    expect_picker_after_turbo_visit(new_admin_job_option_path, "job_type_ids_option")
  end

  it "sets up the space picker on the new contact info form" do
    create(:space)
    expect_picker_after_turbo_visit(new_admin_contact_info_path, "contact_info_space_id")
  end

  it "sets up the manager picker on the space settings page" do
    expect_picker_after_turbo_visit(edit_admin_space_path(create(:space)), "space-manager-select")
  end

  it "sets up the captain search on the new team form" do
    expect_picker_after_turbo_visit(new_admin_team_path, "search_users_add")
  end

  it "sets up the training picker on the new question form" do
    expect_picker_after_turbo_visit(new_question_path, "questions_trainings")
  end

  it "sets up the instructor picker on the new training session form" do
    expect_picker_after_turbo_visit(new_staff_training_session_path(space_id: create(:space).id), "user_id")
  end

  it "sets up the subskill picker on the new learning module form" do
    expect_picker_after_turbo_visit(new_learning_area_path, "learning_module_subskill")
  end
end
