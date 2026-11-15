# frozen_string_literal: true

require "rails_helper"

# The add button beside a file input adds another input row with a button that
# removes it. The add button stays the only element with its id.
RSpec.describe "Added file input rows", type: :system, skip_bullet: true do
  def added(id) = ".input-group:has(> ##{id}) ~ .input-group > button.btn-danger"

  def add_two_rows(id)
    wait_for_app_js
    2.times { find("##{id}").click }
    expect(page).to have_css(added(id), count: 2)
  end

  def expect_one_add_button(id)
    expect(page.evaluate_script("document.querySelectorAll('[id=#{id.to_json}]').length")).to eq(1)
    expect(page).to have_no_css("#{added(id)}[id]")
  end

  def expect_removable_rows(id)
    expect_one_add_button(id)
    first(added(id)).click
    expect(page).to have_css(added(id), count: 1)
  end

  describe "the new proficient project form" do
    it "keeps the gallery add button the only element with its id" do
      log_in_as(create(:user, :admin), to: new_proficient_project_path)
      add_two_rows("new-photo-input")
      expect_removable_rows("new-photo-input")
    end
  end

  describe "the edit proficient project form" do
    it "keeps the gallery add button the only element with its id" do
      log_in_as(create(:user, :admin), to: edit_proficient_project_path(create(:proficient_project)))
      add_two_rows("new-photo-input")
      expect_removable_rows("new-photo-input")
    end
  end

  describe "the new make form" do
    it "keeps the gallery add button the only element with its id" do
      owner = create(:user, :regular_user)
      original = create(:repository, owner: owner, users: [owner])
      log_in_as(create(:user, :regular_user), to: makes_new_path(owner.username, original.id))
      add_two_rows("new-photo-input")
      expect_removable_rows("new-photo-input")
    end
  end
end
