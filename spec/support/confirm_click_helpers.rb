# frozen_string_literal: true

# Clicks on buttons that ask for confirmation, for the browser specs.
module ConfirmClickHelpers
  # Click a button that asks for confirmation, after bringing it into view at
  # once. The page asks for smooth scrolling (Bootstrap's `scroll-behavior:
  # smooth`), so the scroll chromedriver makes before a click is animated, and
  # its press can land while the page is still moving: it hits whatever slid
  # under the pointer and is lost without an error, and no prompt opens. An
  # instant scroll first leaves chromedriver nothing to animate. The button is
  # found enabled, as a confirming button is only once its controller connected.
  # Turning smooth scrolling off for the whole browser is no substitute: Chrome
  # then scrolls a page's autofocused field back into view on the first mouse
  # input, under a press aimed lower down the page.
  def accept_confirm_click(button_text)
    button = find_button(button_text)
    page.execute_script("arguments[0].scrollIntoView({ behavior: 'instant', block: 'center' })", button)
    accept_confirm { button.click }
  end
end

RSpec.configure do |config|
  config.include ConfirmClickHelpers, type: :system
end
