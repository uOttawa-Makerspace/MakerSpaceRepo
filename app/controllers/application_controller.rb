# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, use :null_session instead.
  rescue_from ActionController::ParameterMissing, with: :parameter_missing
  protect_from_forgery with: :null_session,
                       only: proc { |c| c.request.format == "application/json" }
  include ApplicationHelper
  require "zip"
  include Pagy::Method
  before_action :set_locale
  before_action :set_last_seen_at,
                if:
                  proc {
                    signed_in? &&
                      (
                        current_user.last_seen_at.nil? ||
                          current_user.last_seen_at < 15.minutes.ago
                      )
                  }
  helper_method :current_order

  def set_locale
    I18n.locale = params[:locale] || session[:locale] || I18n.default_locale
    session[:locale] = I18n.locale
  end

  def current_order
    session_order = Order.find_by(id: session[:order_id]) unless session[:order_id].nil?
    if session_order.present? && current_user.id.present? &&
         session_order.user_id == current_user.id &&
         session_order.order_status&.name.eql?("In progress")
      return session_order
    end
    session[:order_id] = nil

    if current_user.orders.last.present? &&
         current_user.orders.last.order_status.name.eql?("In progress")
      current_user.orders.last
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
      format.html { redirect_to login_path(back_to: login_back_to) }
      format.js { render js: "window.location.href = '#{login_path}'" }
      format.json { render json: "redirect" }
    end
  end

  # Where to send the user after logging in. Only GET/HEAD URLs can be revisited;
  # a POST/PATCH/DELETE target would 404 as a GET, so for those fall back to the
  # referring page when it is on this host, otherwise nothing.
  def login_back_to
    return request.fullpath if request.get? || request.head?

    referer = URI.parse(request.referer.to_s)
    return unless referer.is_a?(URI::HTTP) && referer.host.present? && referer.host == request.host

    path = referer.request_uri
    path unless URI.parse(path).path == login_path
  rescue URI::InvalidURIError
    nil
  end
  helper_method :login_back_to

  def parameter_missing(exception)
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message }
      format.json { render json: { error: exception.message }, status: 400 }
    end
  end
end
