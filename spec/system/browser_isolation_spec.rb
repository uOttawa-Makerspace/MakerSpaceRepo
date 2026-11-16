# frozen_string_literal: true

require "rails_helper"

# The Chrome session is shared by consecutive system examples. What one example
# leaves in it (a window size, a script still running on its page) must not
# reach the next one.
RSpec.describe "Browser isolation between examples", type: :system, order: :defined, skip_bullet: true do
  describe "console errors" do
    # Waits (with Capybara's retrying) until the scheduled function has run.
    def wait_for_late_failure
      page.document.synchronize { raise Capybara::ExpectationNotMet, "late failure has not run" unless page.evaluate_script("window.lateFailureRan") }
    end

    # Script that runs a function from a timer after delay_ms; the function sets
    # window.lateFailureRan and throws an error with the given message.
    def late_failure_script(message:, delay_ms:)
      <<~JS
        window.lateFailureRan = false;
        window.lateFailure = function () { window.lateFailureRan = true; throw new Error('#{message}'); };
        setTimeout(window.lateFailure, #{delay_ms});
      JS
    end

    it "logs the late error when the page stays alive (the control for the next example)", js: true do
      visit root_path
      page.execute_script(late_failure_script(message: "late failure", delay_ms: 0))
      wait_for_late_failure

      errors = JsErrorCheck.collect(page)
      expect(errors.map { |e| e[:message] }).to include(a_string_matching(/late failure/))
    end

    it "does not report an error that the left page raises after the log was read", js: true do
      visit root_path
      # The same function as the control above, on a timer that cannot fire before the page is left; leaving kills it.
      page.execute_script(late_failure_script(message: "late failure", delay_ms: 30_000))
      expect(page.evaluate_script("window.lateFailureRan")).to be(false)

      expect(JsErrorCheck.collect(page, leave_page: true)).to be_empty
      expect(page.current_url).to eq("about:blank")
      expect(page.evaluate_script("window.lateFailureRan")).to be_nil
    end

    it "returns an error the page logged before it was left, with the page path", js: true do
      visit root_path
      page.execute_script(late_failure_script(message: "early failure", delay_ms: 0))
      wait_for_late_failure

      errors = JsErrorCheck.collect(page, leave_page: true)
      expect(errors.size).to eq(1)
      expect(errors.first[:path]).to eq(root_path)
      expect(errors.first[:message]).to match(/early failure/)
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
