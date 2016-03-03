class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]

  def index
    @users = User.all.order("created_at desc").limit(10)
  end

  def search
    if !params[:q_name].blank?
      @query = params[:q_name]
      @users = User.where("LOWER(name) like LOWER(?)", "%#{@query}%")
    elsif !params[:q_email].blank?
      @query = params[:q_email]
      @users = User.where("LOWER(email) like LOWER(?)", "%#{@query}%")
    end
  end

  def edit
    @rfids = Rfid.recent_unset
  end

  def update
    @user.update!(user_params)
    if rfid = Rfid.where("id = ?", params[:user][:rfid]).first
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
