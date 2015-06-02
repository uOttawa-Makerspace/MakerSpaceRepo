class UsersController < SessionsController

  skip_before_action :session_expiry, only: [:create]
  before_action :current_user, except: [:create]
  before_action :signed_in, except: [:new, :create]
    
  def create
    @user = User.new(user_params)
    @user.pword = params[:user][:password] if @user.valid?
    
    respond_to do |format|
      if @user.save
        session[:user_id], cookies[:user_id] = @user.id, @user.id
        format.html { redirect_to root_path, status: :ok }
        format.json { render json: @user, status: :ok }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def new
  end

  def edit
    render layout: "profile"
  end

  def account_setting
    render layout: "profile"
  end

  def update
    if @user.update(user_params)
      redirect_to edit_user_path(@user), notice: 'Profile updated!'
    else
      render 'edit', alert: 'Something went wrong!'
    end
  end

  def change_password
      flag = false

      if @user.pword == params[:old_password] and
        params[:user][:password] == params[:user][:password_confirmation] then
          @user.pword = params[:user][:password]
          flag = true
      end

      if flag
        @user.save
        redirect_to action: :account_setting, notice: 'Password changed successfully'
      else
        render :account_setting, alert: 'Something went wrong!', layout: "profile"
      end
  end

  def show
  end

  def destroy
    @user.destroy
    session[:user_id] = nil
    redirect_to root_path
  end

private

  def user_params
    params.require(:user).permit(:password, :password_confirmation, :url, 
      :location, :email, :first_name, :last_name, :username, :avatar, 
      :description)
  end

end
