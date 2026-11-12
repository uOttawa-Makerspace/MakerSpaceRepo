# frozen_string_literal: true

require "rails_helper"

# The dark theme fills primary buttons with a darker orange than the light theme,
# and the save button darkens on hover. Pinned as computed styles.
RSpec.describe "Dark theme primary colour contrast", type: :system, skip_bullet: true do
  let(:admin) { create(:user, :admin) }

  def set_theme(theme)
    page.driver.browser.manage.add_cookie(name: "theme", value: theme, path: "/")
  end

  def rgb_of(css) = css.scan(/\d+/).first(3).map { |c| c.to_i / 255.0 }

  def luminance(css)
    r, g, b = rgb_of(css).map { |c| c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4 }
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def white_ratio(css) = 1.05 / (luminance(css) + 0.05)

  def style_of(selector, property)
    page.evaluate_script("getComputedStyle(document.querySelector(#{selector.to_json}))[#{property.to_json}]")
  end

  # Waits for the 0.2s colour transition to finish.
  def expect_style(selector, property, value)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "#{property} is #{style_of(selector, property)}" unless style_of(selector, property) == value
    end
  end

  it "fills primary buttons with a colour that gives white text 4.5:1 in every state, dark theme" do
    visit "/robots.txt"
    set_theme("dark")
    visit forgot_password_path
    expect(page).to have_css("html[data-bs-theme='dark']")
    expect(style_of("main .btn-primary", "backgroundColor")).to eq("rgb(217, 61, 29)")
    expect(white_ratio(style_of("main .btn-primary", "backgroundColor"))).to be >= 4.5
    find("main .btn-primary", match: :first).hover
    expect_style("main .btn-primary", "backgroundColor", "rgb(184, 52, 25)")
  end

  it "keeps the brand orange fill in the light theme" do
    visit "/robots.txt"
    set_theme("light")
    visit forgot_password_path
    expect(page).to have_css("html[data-bs-theme='light']")
    expect(style_of(".btn-primary", "backgroundColor")).to eq("rgb(226, 72, 41)")
  end

  it "darkens the save button on hover instead of fading it, so white text keeps 4.5:1" do
    log_in_as(admin, to: root_path)
    set_theme("light")
    visit search_admin_users_path
    expect(page).to have_css("input.save-button")
    expect(style_of("input.save-button", "opacity")).to eq("1")
    find("input.save-button", match: :first).hover
    expect_style("input.save-button", "backgroundColor", "rgb(73, 121, 121)")
    expect(style_of("input.save-button", "opacity")).to eq("1")
    expect(white_ratio(style_of("input.save-button", "backgroundColor"))).to be >= 4.5
  end
end
