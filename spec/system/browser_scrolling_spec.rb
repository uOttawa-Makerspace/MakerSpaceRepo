# frozen_string_literal: true

require "rails_helper"

# The page asks for smooth scrolling (Bootstrap's `scroll-behavior: smooth`), so
# a scroll the page or chromedriver makes is animated. accept_confirm_click
# (spec/support/confirm_click_helpers.rb) scrolls its button into view instantly
# first, so chromedriver's press cannot land while the page is still moving.
RSpec.describe "Test browser scrolling", type: :system do
  def scroll_result(behaviour)
    page.evaluate_script(<<~JS)
      (function () {
        var root = document.documentElement;
        window.scrollTo({ top: 0, behavior: "instant" });
        var target = Math.min(300, root.scrollHeight - window.innerHeight);
        window.scrollTo({ top: target#{behaviour} });
        return [getComputedStyle(root).scrollBehavior, target, window.scrollY];
      })()
    JS
  end

  before do
    visit root_path
    expect(page).to have_css("img[alt='CEED Logo']")
  end

  it "animates a scroll that names no behaviour, as the page asks for smooth scrolling" do
    css, target, reached = scroll_result("")
    expect(css).to eq("smooth")
    expect(target).to be > 0
    expect(reached).to be < target
  end

  it "lands an instant scroll at once" do
    _css, target, reached = scroll_result(', behavior: "instant"')
    expect(target).to be > 0
    expect(reached).to eq(target)
  end
end
