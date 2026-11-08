# frozen_string_literal: true

# Picks the locale of a request from ?locale=, then the session, then the default.
module RequestLocale
  extend ActiveSupport::Concern

  # I18n.locale is thread-global, so scope it to the request (with_locale
  # restores it afterwards) and ignore unsupported values instead of raising
  # I18n::InvalidLocale.
  def switch_locale(&action)
    session[:locale] = request_locale
    I18n.with_locale(request_locale, &action)
  end

  private

  def request_locale
    available = I18n.available_locales.map(&:to_s)
    candidate = [params[:locale], session[:locale]].find { |l| l.to_s.presence_in(available) }
    candidate ? candidate.to_s.to_sym : I18n.default_locale
  end

  # For rescue_from handlers: they run after the around_action has restored the locale.
  def with_request_locale(&)
    I18n.with_locale(request_locale, &)
  end
end
