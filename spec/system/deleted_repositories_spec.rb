# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Deleted repositories", type: :system do
  let(:admin) { create(:user, :admin) }
  let!(:repo) { create(:repository, title: "Bring me back").tap { |r| r.hide!(by: admin) } }

  before { log_in_as(admin, to: admin_deleted_repositories_path) }

  it "keeps the repository deleted when the confirmation is dismissed" do
    dismiss_confirm("Restore this repository?") { click_button "Restore" }
    expect(page).to have_content("Bring me back")
    expect(Repository.unscoped.find(repo.id).deleted).to be(true)
  end

  it "restores the repository when the confirmation is accepted" do
    accept_confirm("Restore this repository?") { click_button "Restore" }
    expect(page).to have_content("Repository restored.")
    expect(Repository.unscoped.find(repo.id).deleted).to be(false)
  end
end
