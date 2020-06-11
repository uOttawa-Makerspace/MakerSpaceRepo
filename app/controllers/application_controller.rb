class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
	protect_from_forgery with: :null_session, only: Proc.new { |c| c.request.format == 'application/json' }
  include ApplicationHelper

  before_action :set_locale
  before_action :set_last_seen_at, if: proc { signed_in? && (current_user.last_seen_at.nil? || current_user.last_seen_at < 15.minutes.ago) }
  helper_method :current_order

  def set_locale
    I18n.locale = params[:locale] || session[:locale] || I18n.default_locale
    session[:locale] = I18n.locale
  end

  def current_order
    if !session[:order_id].nil?
      Order.find(session[:order_id])
    else
      Order.new
    end
  end

  private
  def set_last_seen_at
    current_user.update_attribute(:last_seen_at, Time.current)
    session[:last_seen_at] = Time.current
  end

  def signed_in
    return if signed_in?
    respond_to do |format|
      format.html { redirect_to login_path }
      format.js   { render js: "window.location.href = '#{login_path}'" }
      format.json { render json: "redirect" }
    end
  end
end
