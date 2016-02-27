class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]

  def index
    @users = User.all
  end

  def edit
    @rfids = Rfid.recent_unset
  end

  def update
    @user.update!(user_params)
    if rfid = Rfid.find(params[:user][:rfid])
      if @user.rfid
        @user.rfid.destroy!
      end
      rfid.user = @user
      rfid.save!
    end
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
