# frozen_string_literal: true

require "rails_helper"

# The hours disclaimer follows the theme chosen in the app (the theme cookie),
# not the operating system's colour scheme.
RSpec.describe "Hours page disclaimer theme", type: :system, skip_bullet: true do
  def set_theme(theme)
    page.driver.browser.manage.add_cookie(name: "theme", value: theme, path: "/")
  end

  def style_of(property)
    page.evaluate_script("getComputedStyle(document.querySelector('#hours-of-operation > p'))[#{property.to_json}]")
  end

  it "tints the disclaimer maroon in the dark theme" do
    visit "/robots.txt"
    set_theme("dark")
    visit hours_path
    expect(page).to have_css("html[data-bs-theme='dark']")
    expect(style_of("backgroundColor")).to eq("rgba(143, 0, 26, 0.2)")
    expect(style_of("borderLeftColor")).to eq("rgb(143, 0, 26)")
  end

  it "keeps the light grey disclaimer in the light theme" do
    visit "/robots.txt"
    set_theme("light")
    visit hours_path
    expect(page).to have_css("html[data-bs-theme='light']")
    expect(style_of("backgroundColor")).to eq("rgb(247, 247, 247)")
  end
end
