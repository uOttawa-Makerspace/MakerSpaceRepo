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

    # Runs window.lateFailure from a timer once the page has had a turn, and
    # reports back through window.lateFailureRan so the run itself is observable.
    let(:schedule_late_failure) do
      <<~JS
        window.lateFailureRan = false;
        window.lateFailure = function () { window.lateFailureRan = true; throw new Error('late failure'); };
        setTimeout(window.lateFailure, 0);
      JS
    end

    it "logs the late error when the page stays alive (the control for the next example)", js: true do
      visit root_path
      page.execute_script(schedule_late_failure)
      wait_for_late_failure

      errors = JsErrorCheck.collect(page)
      expect(errors.map { |e| e[:message] }).to include(a_string_matching(/late failure/))
    end

    it "does not report an error that the left page raises after the log was read", js: true do
      visit root_path
      # The same trigger as the control above, but the page is left first: its timer dies with it.
      page.execute_script(schedule_late_failure.sub("setTimeout(window.lateFailure, 0);", "setTimeout(window.lateFailure, 250);"))
      expect(page.evaluate_script("window.lateFailureRan")).to be(false)

      expect(JsErrorCheck.collect(page, leave_page: true)).to be_empty
      expect(page.current_url).to eq("about:blank")
      expect(page.evaluate_script("window.lateFailureRan")).to be_nil
      expect(JsErrorCheck.collect(page)).to be_empty
    end

    it "returns an error the page logged before it was left, with the page path", js: true do
      visit root_path
      page.execute_script(schedule_late_failure.sub("late failure", "early failure"))
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
