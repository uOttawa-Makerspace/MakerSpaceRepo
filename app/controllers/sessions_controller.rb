class SessionsController < ApplicationController

  before_action :session_expiry, except: [:login_authentication] 
  before_action :update_activity_time
  before_action :current_user, only: [:login]

  def login_authentication

    username_email = params[:username]
    password = params[:password]
    @user = User.authenticate(username_email, password)

    respond_to do |format|
      if @user
        session[:user_id], cookies[:user_id] = @user.id, { value: @user.id, expires: 1.day.from_now }
        format.html { redirect_to session[:back] }
        format.json { render json: { role: :guest }, status: :ok }
      else
        flash.now[:alert] = "Incorrect username or password."
        format.html { render :login }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def login
    session[:back] = request.referrer
  end
  
  def signed_in
    return if signed_in?
    respond_to do |format|
      format.html { redirect_to new_user_path }
      format.js { render :js => "window.location.href = '#{new_user_path}'" }
    end
  end
  
  def logout
    disconnect_user
    @user = User.new
    redirect_to root_path
  end

  def disconnect_user
    session[:user_id] = nil
    cookies.delete :user_id
  end

  def session_expiry
    get_session_time_left
    disconnect_user if @session_time_left <= 0
  end

  def update_activity_time
    session[:expires_at] = 6.hours.from_now
  end

private

  def get_session_time_left
    expire_time = session[:expires_at] || Time.now
    @session_time_left = (expire_time.to_time - Time.now).to_i
  end

end
