# frozen_string_literal: true

require "rails_helper"

# The Chrome session is shared by consecutive system examples. What one example
# leaves in it (a window size, a script still running on its page) must not
# reach the next one.
RSpec.describe "Browser isolation between examples", type: :system, order: :defined, skip_bullet: true do
  describe "console errors" do
    it "does not report an error that the left page raises after the log was read", js: true do
      visit root_path
      page.execute_script("window.lateFailure = function () { throw new Error('late failure'); }")
      expect(JsErrorCheck.collect(page, leave_page: true)).to be_empty

      # With the page still alive this fires and is logged; after leaving it, there is no page to run it.
      page.driver.browser.execute_async_script(<<~JS)
        var done = arguments[0];
        if (window.lateFailure) setTimeout(window.lateFailure, 0);
        setTimeout(done, 20);
      JS
      expect(JsErrorCheck.collect(page)).to be_empty
    end
  end

  describe "window size" do
    it "starts a narrow example (the next one checks it was restored)" do
      visit root_path
      page.driver.browser.manage.window.resize_to(800, 900)
      expect(page.driver.browser.manage.window.size.width).to eq(800)
    end

    it "starts at the standard size after an example resized the window" do
      visit root_path
      size = page.driver.browser.manage.window.size
      expect([size.width, size.height]).to eq(SYSTEM_WINDOW_SIZE)
    end
  end
end
