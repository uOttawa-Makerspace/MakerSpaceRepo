# frozen_string_literal: true

require "rails_helper"

# The add button beside a file input adds another input row with a button that
# removes it. The add button stays the only element with its id, and each
# remove button is announced as a remove button, in the page's language.
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

  def expect_rows_with_remove_label(id, label)
    expect_one_add_button(id)
    expect(page).to have_css("#{added(id)}[aria-label='#{label}']", count: 2)
    expect(find("##{id}")["aria-label"]).not_to eq(label)
    first(added(id)).click
    expect(page).to have_css("#{added(id)}[aria-label='#{label}']", count: 1)
  end

  describe "the project proposal form" do
    let(:user) { create(:user, :regular_user) }

    it "labels the added rows' buttons as remove buttons" do
      log_in_as(user, to: new_project_proposal_path)
      add_two_rows("new-file-input")
      expect_rows_with_remove_label("new-file-input", "Remove")
    end

    it "labels them in French on a French page" do
      log_in_as(user, to: new_project_proposal_path(locale: :fr))
      add_two_rows("new-file-input")
      expect_rows_with_remove_label("new-file-input", "Retirer")
    end
  end

  describe "the new proficient project form" do
    it "labels the added gallery rows' buttons as remove buttons" do
      log_in_as(create(:user, :admin), to: new_proficient_project_path)
      add_two_rows("new-photo-input")
      expect_rows_with_remove_label("new-photo-input", "Remove")
    end
  end

  describe "the edit proficient project form" do
    it "labels the added gallery rows' buttons as remove buttons" do
      log_in_as(create(:user, :admin), to: edit_proficient_project_path(create(:proficient_project)))
      add_two_rows("new-photo-input")
      expect_rows_with_remove_label("new-photo-input", "Remove")
    end
  end

  describe "the new make form" do
    it "labels the added gallery rows' buttons as remove buttons" do
      owner = create(:user, :regular_user)
      original = create(:repository, owner: owner, users: [owner])
      log_in_as(create(:user, :regular_user), to: makes_new_path(owner.username, original.id))
      add_two_rows("new-photo-input")
      expect_rows_with_remove_label("new-photo-input", "Remove")
    end
  end
end
