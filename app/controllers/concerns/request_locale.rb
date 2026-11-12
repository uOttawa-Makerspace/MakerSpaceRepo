# frozen_string_literal: true

# Picks the locale of a request from ?locale=, then the session choice, then the signed-in user's saved language,
# then the default. Only a supported ?locale= is written to the session, so a visit never records the default as
# a choice and a user's saved language still applies until they pick another.
module RequestLocale
  extend ActiveSupport::Concern

  # I18n.locale is thread-global, so scope it to the request (with_locale
  # restores it afterwards) and ignore unsupported values instead of raising
  # I18n::InvalidLocale.
  def switch_locale(&action)
    explicit = chosen_locale(params[:locale])
    session[:locale] = explicit if explicit
    I18n.with_locale(request_locale, &action)
  end

  private

  def request_locale
    candidate = [params[:locale], session[:locale], saved_user_locale].lazy.filter_map { |l| chosen_locale(l) }.first
    candidate || I18n.default_locale
  end

  # The language saved on the signed-in user's account; controllers with a session user override this.
  def saved_user_locale = nil

  def chosen_locale(value)
    value.to_s.presence_in(I18n.available_locales.map(&:to_s))&.to_sym
  end

  # For rescue_from handlers: they run after the around_action has restored the locale.
  def with_request_locale(&)
    I18n.with_locale(request_locale, &)
  end
end
