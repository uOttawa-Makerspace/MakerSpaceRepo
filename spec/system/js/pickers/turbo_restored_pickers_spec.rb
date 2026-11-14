# frozen_string_literal: true

require "rails_helper"

# Searchable pickers (TomSelect) on a page Turbo restores from its cache: the
# copy of the page still carries the markup of the pickers it was left with,
# and each select must end up with one working picker, as on a fresh visit.
RSpec.describe "Pickers on a page restored from the Turbo cache", type: :system, skip_bullet: true do
  def expect_one_working_picker(id)
    expect(page).to have_css("##{id} ~ .ts-wrapper", count: 1, visible: :all)
    expect(page.evaluate_script("Boolean(document.getElementById(#{id.to_json}).tomselect)")).to be(true)
  end

  it "keeps one working picker per select on the new repository form" do
    author = create(:user, :regular_user)
    path = new_repository_path(user_username: author.username)
    log_in_as(author, to: path)
    expect(page).to have_css("#owner_select.tomselected", visible: :all)
    leave_and_restore(path)
    %w[owner_select repository_categories repository_equipments repository_project_proposal_id].each do |id|
      expect_one_working_picker(id)
    end
  end

  describe "with lockers on" do
    include_context "with lockers on"

    it "keeps one working picker per locker size select on the locker inventory" do
      create(:locker, specifier: "101", locker_size: size_small, audience: "general")
      log_in_as(admin, to: lockers_path)
      expect(page).to have_css("select.locker-variant-select.tomselected", visible: :all)
      leave_and_restore(lockers_path)
      ids = page.evaluate_script("Array.from(document.querySelectorAll('select.locker-variant-select')).map((s) => s.id)")
      expect(ids).not_to be_empty
      expect(page).to have_css("select.locker-variant-select + .ts-wrapper", count: ids.size, visible: :all)
      expect(page).to have_no_css("select.locker-variant-select + .ts-wrapper + .ts-wrapper", visible: :all)
    end
  end

  it "keeps one working program picker on the sign-up form" do
    visit new_user_path
    expect(page).to have_css("#user_program.tomselected", visible: :all)
    leave_and_restore(new_user_path)
    expect_one_working_picker("user_program")
  end

  # Opens the page, waits for its picker, then leaves and restores it.
  def restore_with_picker(user, path, id)
    log_in_as(user)
    visit path
    expect(page).to have_css("##{id}.tomselected", visible: :all)
    leave_and_restore(path)
    expect_one_working_picker(id)
  end

  describe "with lockers on" do
    include_context "with lockers on"

    it "keeps one working preferred locker picker on the locker request form" do
      create(:locker, specifier: "A1", locker_size: size_small, audience: "general")
      restore_with_picker(create(:user, :regular_user), new_locker_rental_path, "locker_rental_preferred_locker_id")
    end
  end

  it "keeps one working certification search on the volunteer stats page" do
    restore_with_picker(create(:user, :volunteer_with_volunteer_program), my_stats_volunteers_path, "training-search-select")
  end

  it "keeps one working user picker on the new volunteer event form" do
    restore_with_picker(create(:user, :admin), new_event_volunteers_path, "user_select")
  end

  it "keeps one working member picker on a repository page for its owner" do
    owner = create(:user, :regular_user)
    repository = create(:repository, owner: owner, user_id: owner.id)
    path = repository_path(user_username: owner.username, id: repository.id)
    restore_with_picker(owner, path, "repo_owner_owner_username")
  end

  it "keeps one working user picker on the booking page admin panel" do
    %i[pending approved rejected].each { |status| create(:booking_status, status) }
    subspace = create(:sub_space, space: create(:space))
    admin = create(:user, :admin, booking_approval: true)
    restore_with_picker(admin, sub_space_booking_index_path(room: subspace.id), "user_booking_select")
  end

  it "keeps one working instructor picker on the new training session form" do
    restore_with_picker(create(:user, :admin), new_staff_training_session_path(space_id: create(:space).id), "user_id")
  end

  it "keeps one working staff picker on a job order" do
    seed_job_statuses!
    seed_job_order_message!
    order = make_job_order!(owner: create(:user, :regular_user), status_key: :staff_approval)
    restore_with_picker(create(:user, :admin), job_order_path(order), "jo-staff-select")
  end

  it "keeps one working subskill picker on the new learning module form" do
    restore_with_picker(create(:user, :admin), new_learning_area_path, "learning_module_subskill")
  end

  it "keeps one working training picker on the new question form" do
    restore_with_picker(create(:user, :admin), new_question_path, "questions_trainings")
  end

  describe "on admin forms" do
    let(:admin) { create(:user, :admin) }

    it "keeps one working skill picker per language on the new training form" do
      log_in_as(admin, to: new_admin_training_path)
      expect(page).to have_css("#training_list_of_skills_fr.tomselected", visible: :all)
      leave_and_restore(new_admin_training_path)
      # The two skill selects share a parent, so each is checked by its own next sibling.
      %w[training_list_of_skills_en training_list_of_skills_fr].each do |id|
        expect(page).to have_css("##{id} + .ts-wrapper", count: 1, visible: :all)
        expect(page).to have_no_css("##{id} + .ts-wrapper + .ts-wrapper", visible: :all)
        expect(page.evaluate_script("Boolean(document.getElementById(#{id.to_json}).tomselect)")).to be(true)
      end
    end

    it "keeps one working job type picker on the new job option form" do
      create(:job_type)
      restore_with_picker(admin, new_admin_job_option_path, "job_type_ids_option")
    end

    it "keeps one working space picker on the new contact info form" do
      create(:space)
      restore_with_picker(admin, new_admin_contact_info_path, "contact_info_space_id")
    end

    it "keeps one working manager picker on the space settings page" do
      restore_with_picker(admin, edit_admin_space_path(create(:space)), "space-manager-select")
    end

    it "keeps one working captain search on the new team form" do
      restore_with_picker(admin, new_admin_team_path, "search_users_add")
    end
  end

  describe "on pages whose script once ran only when first loaded" do
    let(:admin) { create(:user, :admin) }

    it "keeps one working user picker on the new project kit form" do
      restore_with_picker(admin, new_project_kit_path, "kit_user_select")
    end

    it "keeps one working category picker and link buttons on the new project proposal form" do
      restore_with_picker(admin, new_project_proposal_path, "project_proposal_categories")
      click_button "link-list"
      expect(page).to have_css(".main_ul li input", count: 1)
      click_button "remove-link-list"
      expect(page).to have_no_css(".main_ul li")
    end

    it "keeps one working printer picker and model code on the printers page" do
      create(:printer_type, :UM2P)
      create(:printer_type, :RPL2)
      restore_with_picker(admin, printers_path, "remove_printer")
      select "Ultimaker 2+ (UM2P)", from: "model_id"
      expect(page).to have_css("#newPrinterCode", exact_text: "UM2P")
      select "Replicator 2 (RPL2)", from: "model_id"
      expect(page).to have_css("#newPrinterCode", exact_text: "RPL2")
    end

    it "keeps one working staff picker on the add new staff page" do
      restore_with_picker(admin, admin_add_new_staff_index_path, "new_staff_select")
    end

    it "sets up the staff picker on the add new staff page reached by a Turbo visit" do
      log_in_as(admin, to: admin_users_path)
      wait_for_app_js
      page.execute_script("Turbo.visit(#{admin_add_new_staff_index_path.to_json})")
      expect(page).to have_current_path(admin_add_new_staff_index_path)
      expect(page).to have_css("#new_staff_select.tomselected", visible: :all)
      expect_one_working_picker("new_staff_select")
    end

    it "keeps one working supervisor and department picker on the new key request form" do
      create(:space)
      restore_with_picker(create(:user, :staff), new_key_request_path, "supervisor-select")
      expect_one_working_picker("space-select")
    end
  end
end
