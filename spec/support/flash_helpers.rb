# frozen_string_literal: true

# Reads the flash message a page shows after a form is submitted from the
# flash element alone (#flash in every layout that shows flash messages). A
# whole-page text check makes the browser work out the visible text of the
# entire page on every poll, which takes a second or more on a large page under
# load, and while it does, the page cannot draw the response being waited for.
module FlashHelpers
  def expect_flash(message)
    expect(page).to have_css("#flash", text: message)
  end
end

RSpec.configure do |config|
  config.include FlashHelpers, type: :system
end
