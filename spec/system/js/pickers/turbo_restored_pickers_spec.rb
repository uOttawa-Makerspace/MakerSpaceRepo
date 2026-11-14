# frozen_string_literal: true

require "rails_helper"

# Searchable pickers (TomSelect) on a page Turbo restores from its cache: the
# copy of the page still carries the markup of the pickers it was left with,
# and each select must end up with one working picker, as on a fresh visit.
RSpec.describe "Pickers on a page restored from the Turbo cache", type: :system, skip_bullet: true do
  # Visits the same page again with Turbo, then goes back to the cached copy
  # and waits until the page scripts have run over it.
  def leave_and_restore(path)
    wait_for_app_js
    page.execute_script("Turbo.visit(#{"#{path}#{path.include?('?') ? '&' : '?'}revisit=1".to_json})")
    expect(page).to have_current_path(/revisit=1/)
    wait_for_app_js
    # Set only after the forward visit has loaded, so it marks the load of the
    # restored page; it runs after the page scripts' own handlers.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:load", () => {
        document.documentElement.dataset.restoredLoad = "done";
      }, { once: true });
    JS
    page.go_back
    expect(page).to have_css("html[data-restored-load='done']", visible: :all)
  end

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
end
