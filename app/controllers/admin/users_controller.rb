class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :make_admin]

  def index
    @users = User.all
  end

  def show
  end

  def make_admin
    @user.role = 'admin'
    @user.save!
    binding.pry
    redirect_to admin_user_path
  end

  private

  def load_user
    @user = User.find(params[:id])
  end
end
