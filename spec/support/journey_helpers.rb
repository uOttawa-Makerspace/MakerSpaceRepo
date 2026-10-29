# frozen_string_literal: true

# Helpers for the cross-role browser journeys in spec/system/journeys.
module JourneyHelpers
  # Run the block as a separate browser session (own cookies / own Chrome),
  # then apply the same SEVERE-console-error check that system.rb applies to
  # the default session (sessions other than :default are not covered by the
  # after hook). `allow_console:` lists regexes for errors this step
  # deliberately provokes (e.g. the 422 of a rejected form post).
  def as_actor(name, allow_console: [], &block)
    using_session(name) do
      begin
        block.call
      rescue Exception # rubocop:disable Lint/RescueException
        # the after hook only snapshots the default session
        begin
          shot = Capybara.save_path.join("actor_#{name}_#{Time.now.to_i}")
          page.save_screenshot("#{shot}.png")
          page.save_page("#{shot}.html")
          SystemDiagnostics.write("actor_#{name}_#{Time.now.to_i}", page, label: name.to_s)
        rescue StandardError
          nil
        end
        raise
      end
      errors = JsErrorCheck.collect(page).reject { |e| allow_console.any? { |re| e[:message].match?(re) } }
      raise "Unallowlisted SEVERE console errors for #{name}:\n#{errors.map { |e| e[:message] }.join("\n")}" if errors.any?
    end
  end

  # Mails are delivered through ActiveJob (:test adapter in this env); run
  # whatever the Puma thread enqueued and return the delivered messages.
  def deliver_mail
    perform_enqueued_jobs
    ActionMailer::Base.deliveries
  end

  def mails_to(email)
    deliver_mail.select { |m| Array(m.to).include?(email) }
  end

  # Capybara-style wait for a database condition written by the page's JS
  # (retries until Capybara.default_max_wait_time, never sleeps blindly).
  def wait_until(message = "condition not met")
    page.document.synchronize { raise Capybara::ExpectationNotMet, message unless yield }
  end

  # Wait until a Bootstrap modal has FINISHED opening, not just got `.show`.
  # Bootstrap adds `.show` (and aria-modal) at the START of the 300 ms fade, and
  # `shown.bs.modal` fires at its end; the only DOM-observable signal of the end
  # is the transition itself: the modal is fully opaque and its dialog has
  # reached its resting transform. Use before typing/clicking inside a modal.
  def wait_for_modal_ready(selector)
    expect(page).to have_css("#{selector}.show", visible: :all)
    page.document.synchronize do
      done = page.evaluate_script(<<~JS, selector)
        (function (sel) {
          var m = document.querySelector(sel);
          if (!m || !m.classList.contains("show")) return false;
          var d = m.querySelector(".modal-dialog");
          var t = getComputedStyle(d).transform;
          var still = t !== "none" && t !== "matrix(1, 0, 0, 1, 0, 0)";
          return getComputedStyle(m).opacity === "1" && !still &&
            document.querySelectorAll(".modal-backdrop.fade:not(.show)").length === 0;
        })(arguments[0])
      JS
      raise Capybara::ExpectationNotMet, "modal #{selector} still opening" unless done
    end
  end

  # Uncheck a checkbox and CONFIRM it took. Capybara's `uncheck` is a native
  # click and never verifies the result: if the layout moves between
  # chromedriver's hit-test and the mouse press (smooth scroll-into-view, the
  # sticky header shrinking on scroll, Tom Select swapping in its control), the
  # press lands beside the box, the click is silently lost and the form later
  # submits the box as still checked. Re-click until the box is observed
  # unchecked (retries only while it is not; never a blind sleep).
  def uncheck_and_confirm(locator, **options)
    page.document.synchronize do
      uncheck(locator, **options)
      raise Capybara::ExpectationNotMet, "#{locator.inspect} is still checked after uncheck" if has_checked_field?(locator, wait: 0, **options)
    end
  end

  def app_url
    "http://#{page.server.host}:#{page.server.port}"
  end

  # Plain HTTP call to the running Capybara server (no browser): used for
  # machine-to-machine callbacks such as the Shopify webhooks.
  # `shopify_signed: true` adds the X-Shopify-Hmac-Sha256 header over the raw body.
  def post_json_to_app(path, body, shopify_signed: false)
    uri = URI("#{app_url}#{path}")
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = body.to_json
    req[ShopifyWebhookHelpers::SHOPIFY_HMAC_HEADER] = shopify_hmac_for(req.body) if shopify_signed
    Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  end

  def log_out
    visit logout_path
    expect(page).to have_link("Log In").or have_css("a[href='#{login_path}']")
  end

  # First link in a delivered mail whose URL matches `pattern`, as a path +
  # query (mails are built against the configured default host, not the
  # Capybara server, so callers `visit` the path).
  def link_path_in_mail(mail, pattern)
    body = CGI.unescapeHTML((mail.html_part || mail.text_part || mail).body.decoded)
    url = body[%r{https?://[^\s"'<>]*#{pattern.source}[^\s"'<>]*}]
    raise "no link matching #{pattern} in mail #{mail.subject.inspect}" unless url

    uri = URI.parse(url)
    [uri.path, uri.query].compact.join("?")
  end
end

RSpec.configure do |config|
  config.include JourneyHelpers, type: :system
end
