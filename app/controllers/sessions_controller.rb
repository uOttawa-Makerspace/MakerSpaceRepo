# frozen_string_literal: true

class SessionsController < ApplicationController
  include ActionView::Helpers::DateHelper

  before_action :session_expiry, except: [:login_authentication]
  before_action :update_activity_time
  before_action :current_user, only: [:login]
  before_action :authorized_repo_ids
  # Password-guess budget shared with SamlIdpController (same limit, window and
  # cache key), so the two sign-in surfaces cannot be alternated to double it.
  SIGN_IN_RATE_LIMIT = { to: 10, within: 3.minutes, scope: "password-sign-in" }.freeze

  rate_limit(**SIGN_IN_RATE_LIMIT, only: :login_authentication, with: -> {
    render status: :too_many_requests, json: { error: "Too many requests" }
  })

  SUPPORT_EMAIL = "uottawa.makerepo@gmail.com"
  
  def login_authentication
    @user = sign_in(params[:username_email], params[:password])

    respond_to do |format|
      if @user
        @user.update(last_signed_in_time: DateTime.now)
        format.html { redirect_to(safe_back_to || root_path) }
        format.json do
          render json: {
                   user: @user.as_json,
                   signed_in: true,
                   token: @user.token
                 }
        end
        format.json { render json: { role: :guest }, status: :ok }
      elsif @sign_in_refusal == :locked
        @user = User.new
        locked_user = User.username_or_email(params[:username_email])
        format.html do
          flash.now[:alert] = ActionController::Base.helpers.sanitize("""
          Your account has been locked due to too many failed login attempts. 
          Please #{view_context.link_to('contact an administrator', "mailto:#{SUPPORT_EMAIL}?subject=Account%20Locked", class: 'text-primary')} 
          to unlock your account#{lock_wait_suffix(locked_user)}.
          """)
          render :login, status: :unprocessable_content
        end
        format.json do
          render json: {
                   error:
                     "Your account has been locked due to too many failed login attempts. Please contact an administrator at #{SUPPORT_EMAIL} to unlock your account#{lock_wait_suffix(locked_user)}.",
                   support_email: SUPPORT_EMAIL
                 },
                 status: :unprocessable_content
        end
      elsif @sign_in_refusal == :unconfirmed
        @user = User.new
        format.html do
          flash.now[
            :alert
          ] = ActionController::Base.helpers.sanitize("Please confirm your account before logging in, you can resend the email #{view_context.link_to "here", resend_email_confirmation_path(email: params[:username_email]), class: "text-primary"}")
          render :login
        end
        format.json do
          render json: "Account not confirmed", status: :unprocessable_content
        end
      elsif @sign_in_refusal == :inactive
        @user = User.new
        inactive_message =
          "Your account is inactive. Please contact an administrator at #{SUPPORT_EMAIL}."
        format.html do
          flash.now[:alert] = inactive_message
          render :login
        end
        format.json do
          render json: { error: inactive_message, support_email: SUPPORT_EMAIL },
                 status: :unprocessable_content
        end
      else
        @user = User.new
        user = User.username_or_email(params[:username_email])
        if user
          error_message =
            (
              if user.auth_attempts >= User::MAX_AUTH_ATTEMPTS
                format.html? ? 
                  "Your account has been locked due to too many failed login attempts. #{view_context.link_to 'Contact support', "mailto:#{SUPPORT_EMAIL}?subject=Account%20Locked%20-%20#{user.username}", class: 'text-primary'} to unlock your account#{lock_wait_suffix(user, 'try again in')}." :
                  "Your account has been locked due to too many failed login attempts. Contact support at #{SUPPORT_EMAIL} to unlock your account#{lock_wait_suffix(user, 'try again in')}."
              elsif user.auth_attempts > 1
                "Incorrect password. You have #{User::MAX_AUTH_ATTEMPTS - user.auth_attempts} attempts left before your account is locked."
              else
                "Incorrect password."
              end
            )
        else
          error_message =
            "Could not find user with email or username: #{params[:username_email]}"
        end
        format.html do
          flash[:alert] = error_message
          render :login, status: :unprocessable_content
        end
        format.json do
          json_response = { error: error_message }
          json_response[:support_email] = SUPPORT_EMAIL if user&.auth_attempts&.>= User::MAX_AUTH_ATTEMPTS
          render json: json_response, status: :unprocessable_content
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
    leaving = current_user
    sign_out
    leaving.disconnect_cable! if leaving.persisted?
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

  # The one private-repository rule: admin, staff, the owner or a member
  # (user_id / repository.users), or a password already entered this session
  # (the session stores the repository id, never the raw URL segment).
  def repository_unlocked?(repository)
    authorized_repo_ids.include?(repository.id) || @user.admin? ||
      @user.staff? || repository.owned_by?(@user)
  end

  # Redirects to the password page when a private repository is still locked.
  def ensure_repository_unlocked(repository)
    return if repository.nil? || !repository.private? || repository_unlocked?(repository)

    redirect_to password_entry_repository_path(repository.user_username, repository.id)
  end

  def get_session_time_left
    @session_time_left = SessionAuthenticator.seconds_left(session)
  end
end
