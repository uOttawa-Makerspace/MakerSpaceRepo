# frozen_string_literal: true

# Going back to a page with Turbo, in system specs about how a page behaves
# when Turbo shows it again.
module TurboRestoreHelpers
  # Visits the same page again with Turbo, then goes back to it and waits
  # until the page scripts have run over the page shown.
  #
  # Each wait is on the turbo:load of that visit, with its listener added
  # before the visit starts. Turbo changes the URL before the new page is in
  # place and the page scripts have run, so neither the URL nor a listener
  # added after it changes tells that the forward visit has loaded.
  def leave_and_restore(path)
    wait_for_app_js
    visit_with_turbo_and_wait("forward") do
      page.execute_script("Turbo.visit(#{"#{path}#{path.include?('?') ? '&' : '?'}revisit=1".to_json})")
    end
    expect(page).to have_current_path(/revisit=1/)
    visit_with_turbo_and_wait("restored") { page.go_back }
  end

  private

  # Marks the next turbo:load as the given step, runs the visit and waits for
  # that load. The listener runs after the page scripts' own handlers.
  def visit_with_turbo_and_wait(step)
    page.execute_script(<<~JS, step)
      const step = arguments[0];
      document.addEventListener("turbo:load", () => {
        document.documentElement.dataset.turboRestoreStep = step;
      }, { once: true });
    JS
    yield
    expect(page).to have_css("html[data-turbo-restore-step='#{step}']", visible: :all)
  end
end

RSpec.configure do |config|
  config.include TurboRestoreHelpers, type: :system
end
