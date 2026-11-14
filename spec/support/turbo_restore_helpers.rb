# frozen_string_literal: true

# Going back to a page with Turbo, in system specs about how a page behaves
# when Turbo shows it again.
module TurboRestoreHelpers
  # Visits the same page again with Turbo, then goes back to it and waits
  # until the page scripts have run over the page shown.
  def leave_and_restore(path)
    wait_for_app_js
    page.execute_script("Turbo.visit(#{"#{path}#{path.include?('?') ? '&' : '?'}revisit=1".to_json})")
    expect(page).to have_current_path(/revisit=1/)
    wait_for_app_js
    # Set only after the forward visit has loaded, so it marks the load of the
    # page gone back to; it runs after the page scripts' own handlers.
    page.execute_script(<<~JS)
      document.addEventListener("turbo:load", () => {
        document.documentElement.dataset.restoredLoad = "done";
      }, { once: true });
    JS
    page.go_back
    expect(page).to have_css("html[data-restored-load='done']", visible: :all)
  end
end

RSpec.configure do |config|
  config.include TurboRestoreHelpers, type: :system
end
