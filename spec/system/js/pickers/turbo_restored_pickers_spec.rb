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
    page.execute_script("Turbo.visit(#{"#{path}?revisit=1".to_json})")
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
end
