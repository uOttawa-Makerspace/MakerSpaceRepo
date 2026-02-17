# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, use :null_session instead.
  rescue_from ActionController::ParameterMissing, with: :parameter_missing
  protect_from_forgery with: :exception, unless: -> { request.format.json? }
  protect_from_forgery with: :null_session, if: -> { request.format.json? }
  include ApplicationHelper
  require "zip"
  require "will_paginate/array"
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
    if !session[:order_id].nil?
      Order.find(session[:order_id])
    elsif current_user.orders.last.present? &&
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
      format.html { redirect_to login_path(back_to: request.fullpath) }
      format.js { render js: "window.location.href = '#{login_path}'" }
      format.json { render json: "redirect" }
    end
  end

  def parameter_missing(exception)
    respond_to do |format|
      format.html { redirect_to root_path, alert: exception.message }
      format.json { render json: { error: exception.message }, status: 400 }
    end
  end
end