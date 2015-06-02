class SessionsController < ApplicationController

  before_action :session_expiry, except: [:login_authentication] 
  before_action :update_activity_time
  before_action :current_user, only: [:login]

  def login_authentication

    username_email = params[:username]
    password = params[:password]

    @user = User.authenticate(username_email, password)

    if @user
      session[:user_id], cookies[:user_id] = @user.id, @user.id
      redirect_to root_path
    else
      render :login
    end
    
  end

  def login
  end
  
  def signed_in
    return redirect_to root_path unless signed_in?
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
    session[:expires_at] = 30.minutes.from_now
  end

private

  def get_session_time_left
    expire_time = session[:expires_at] || Time.now
    @session_time_left = (expire_time.to_time - Time.now).to_i
  end

end
