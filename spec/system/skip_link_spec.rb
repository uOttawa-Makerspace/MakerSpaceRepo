# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Skip link", type: :system do
  it "is the first tab stop, shows on focus and moves focus to the main content" do
    visit root_path

    page.send_keys(:tab)
    link = page.find("a.skip-link", match: :first)
    expect(page.evaluate_script("document.activeElement.classList.contains('skip-link')")).to be true
    expect(link).to be_visible

    page.send_keys(:enter)
    expect(page.evaluate_script("document.activeElement.id")).to eq("main-content")
  end
end
