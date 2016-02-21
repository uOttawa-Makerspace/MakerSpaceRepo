class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]

  def index
    @users = User.all
  end

  def edit
  end

  def update
    @user.update!(user_params)
    redirect_to edit_admin_user_path(@user)
  end

  private

  def user_params
    params.require(:user).permit(:gender, :faculty, :use, :role)
  end

  def load_user
    @user = User.find(params[:id])
  end
end
