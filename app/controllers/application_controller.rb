class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
	protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format == 'application/json' }
  include ApplicationHelper

  before_action :set_locale
  before_action :set_last_seen_at, if: proc { user_signed_in? && (user.last_seen_at.nil? || user.last_seen_at < 15.minutes.ago) }


  def set_locale
    I18n.locale = params[:locale] || session[:locale] || I18n.default_locale
    session[:locale] = I18n.locale
  end

  private
  def set_last_seen_at
    current_user.update_column(:last_seen_at, Time.now)
  end
end
