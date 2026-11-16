# frozen_string_literal: true

# The language switch in the page header. It sets the language of the pages (the session, as switch_locale does
# for ?locale=) and, for a signed-in user, saves it on their account so mail to them is sent in it. It then
# returns to the page the user was on, when that is a path on this site, and to the home page otherwise (the sign-in page for a switch made there).
class LocalesController < ApplicationController
  def update
    chosen = params[:locale].to_s.presence_in(I18n.available_locales.map(&:to_s))
    if chosen
      session[:locale] = chosen
      current_user.update_column(:locale, chosen) if signed_in? && current_user.locale != chosen
    end
    redirect_to safe_back_to(params[:return_to]) || fallback_path
  end

  private

  # A sign-in page (also a failed sign-in shown at its form post address) is not a return target, but the user
  # switching language there stays on the sign-in page.
  def fallback_path
    login_page_path?(params[:return_to].to_s.split("?").first) ? login_path : root_path
  end
end
