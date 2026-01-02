# frozen_string_literal: true

class SessionsController < ApplicationController
  include ActionView::Helpers::DateHelper

  before_action :session_expiry, except: [:login_authentication]
  before_action :update_activity_time
  before_action :current_user, only: [:login]
  before_action :authorized_repo_ids
  before_action :rate_limit, only: [:login_authentication]

  def rate_limit
    ip = request.env["REMOTE_ADDR"]
    key = "login_#{ip}"
    count = Rails.cache.fetch(key)
    unless count
      Rails.cache.write(key, 1, expires_in: 1.minute)
      count = 1
    end
    Rails.cache.write(key, count.to_i + 1, expires_in: 1.minute)
    render status: 429, json: { error: "Too many requests" } if count.to_i > 10
  end

  def login_authentication
    if User.username_or_email(params[:username_email])
      user = User.username_or_email(params[:username_email])
      if user.locked?
        if user.locked_until < DateTime.now
          user.update(locked: false)
          user.update(auth_attempts: 0)
        else
          respond_to do |format|
            format.html do
              flash[
                :alert
              ] = "Your account has been locked due to too many failed login attempts. Please contact an administrator to unlock your account or wait #{distance_of_time_in_words user.locked_until, DateTime.now}."
              render :login
            end
            format.json do
              render json: {
                       error:
                         "Your account has been locked due to too many failed login attempts. Please contact an administrator to unlock your account or wait #{distance_of_time_in_words user.locked_until, DateTime.now}."
                     },
                     status: :unprocessable_entity
            end
          end
          return
        end
      end
    end
    @user = sign_in(params[:username_email], params[:password])

    respond_to do |format|
      if @user
        if @user.confirmed?
          @user.update(last_signed_in_time: DateTime.now)
          # if request.env["HTTP_REFERER"] == login_authentication_url
          #   format.html { redirect_to root_path }
          # else
          #   format.html { redirect_back(fallback_location: root_path) }
          # end
          format.html { redirect_to(params[:back_to] || root_path) }
          format.json do
            render json: {
                     user: @user.as_json,
                     signed_in: true,
                     token: @user.token
                   }
          end
        else
          @user = User.new
          session[:user_id] = nil
          format.html do
            flash.now[
              :alert
            ] = "Please confirm your account before logging in, you can resend the email #{view_context.link_to "here", resend_email_confirmation_path(email: params[:username_email]), class: "text-primary"}".html_safe
            render :login
          end
          format.json do
            render json: "Account not confirmed", status: :unprocessable_entity
          end
        end
        format.json { render json: { role: :guest }, status: :ok }
      else
        @user = User.new
        user = User.username_or_email(params[:username_email])
        if user
          error_message =
            (
              if user.auth_attempts >= User::MAX_AUTH_ATTEMPTS
                "Your account has been locked due to too many failed login attempts. You can try again in #{distance_of_time_in_words user.locked_until, DateTime.now}."
              elsif user.auth_attempts > 1
                "Incorrect password. You have #{User::MAX_AUTH_ATTEMPTS - user.auth_attempts} attempts left before your account is locked."
              else
                "Incorrect password."
              end
            )
        else
          error_message =
            "Could not find user with email or username #{params[:username_email]}"
        end
        format.html do
          flash[:alert] = error_message
          render :login, status: :unprocessable_entity
        end
        format.json do
          render json: { error: error_message }, status: :unprocessable_entity
        end
      end
    end
  end

  def check_signed_in
    if signed_in?
      render json: {
               signed_in: "true",
               user: @user.as_json,
               token: @user.token
             }
    else
      render json: { signed_in: "false" }
    end
  end

  def login
    redirect_to root_path if signed_in?
  end

  def logout
    sign_out
    @user = User.new
    respond_to do |format|
      format.html { redirect_to root_path }
      format.json { render json: { logout: "true" } }
    end
  end

  def session_expiry
    get_session_time_left
    sign_out if @session_time_left <= 0
  end

  def update_activity_time
    session[:expires_at] = 72.hours.from_now
  end

  def authorized_repo_ids
    session[:authorized_repo_ids] ||= []
  end

  def selected_dates
    session[:selected_dates] ||= []
  end

  def resend_email_confirmation
    @email = params[:email]
  end

  private

  def get_session_time_left
    expire_time = session[:expires_at] || 72.hours.from_now
    @session_time_left = (expire_time.to_time - Time.zone.now).to_i
  end
end
