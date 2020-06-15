# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :session_expiry, except: [:login_authentication]
  before_action :update_activity_time
  before_action :current_user, only: [:login]
  before_action :authorized_repo_ids

  def login_authentication
    @user = sign_in(params[:username_email], params[:password])

    respond_to do |format|
      if @user
        if request.env['HTTP_REFERER'] == login_authentication_url
          format.html { redirect_to root_path }
        else
          format.html { redirect_back(fallback_location: root_path) }
        end
        format.json { render json: { role: :guest }, status: :ok }
      else
        @user = User.new
        @placeholder = params[:username_email]
        flash.now[:alert] = 'Incorrect username or password.'
        format.html { render :login }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def login
    if signed_in?
      flash[:alert] = 'You are already logged in.'
      redirect_to root_path
    end
    @user = User.new
    session[:back] = request.referer
  end

  def signed_in
    return if signed_in?

    respond_to do |format|
      format.html { redirect_to login_path }
      format.js   { render js: "window.location.href = '#{login_path}'" }
      format.json { render json: 'redirect' }
    end
  end

  def logout
    sign_out
    @user = User.new
    redirect_to root_path
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

  private

  def get_session_time_left
    expire_time = session[:expires_at] || Time.zone.now
    @session_time_left = (expire_time.to_time - Time.zone.now).to_i
  end
end
