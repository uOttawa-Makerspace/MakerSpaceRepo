# frozen_string_literal: true

require "rails_helper"

# The page asks for smooth scrolling (Bootstrap's `scroll-behavior: smooth`).
# The test browser scrolls at once anyway, so the scroll chromedriver makes
# before a click has finished when the press lands (spec/support/system.rb).
RSpec.describe "Test browser scrolling", type: :system do
  it "scrolls at once although the page asks for smooth scrolling" do
    visit root_path
    expect(page).to have_css("img[alt='CEED Logo']")

    behaviour, target, reached = page.evaluate_script(<<~JS)
      (function () {
        var root = document.documentElement;
        var target = Math.min(300, root.scrollHeight - window.innerHeight);
        window.scrollTo(0, target);
        return [getComputedStyle(root).scrollBehavior, target, window.scrollY];
      })()
    JS

    expect(behaviour).to eq("smooth")
    expect(target).to be > 0
    expect(reached).to eq(target)
  end
end
