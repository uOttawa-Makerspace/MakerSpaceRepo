class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]
  
  layout 'admin_area'

  def index
    @edit_users = User.all.order("created_at desc").limit(15)
  end

  def search
    if !params[:q].blank?
      @query = params[:q]
      if params[:filter] == "Name"
        @edit_users = User.where("LOWER(name) like LOWER(?)", "%#{@query}%")
      elsif params[:filter] == "Email"
        @edit_users = User.where("LOWER(email) like LOWER(?)", "%#{@query}%")
      elsif params[:filter] == "Username"
        @edit_users = User.where("LOWER(username) like LOWER(?)", "%#{@query}%")
      else
        @edit_users = User.where('name like LOWER(?) OR email like LOWER(?) OR username like LOWER(?)', "%#{@query}%", "%#{@query}%", "%#{@query}%")
      end
    end
  end

  def edit
    @rfids = Rfid.recent_unset
    @certifications = @edit_user.certifications
  end

  def update
    @edit_user.certifications.destroy_all
    @edit_user.update!(user_params)
    if !params[:user][:rfid].blank? && rfid = Rfid.where("id = ?", params[:user][:rfid]).first
      if @edit_user.rfid
        @edit_user.rfid.destroy!
      end
      rfid.user = @edit_user
      rfid.save!
    end
    if @edit_user.update(user_params)
      create_certifications
      render json: { redirect_uri: "#{admin_users_path}" }
      flash[:notice] = "User information updated!"
      
    end
  end

  private

  def user_params
    params.require(:user).permit(:gender, :faculty, :use, :role)
  end

  def load_user
    @edit_user = User.find(params[:id])
  end
  
  def create_certifications
    params['certifications'].first(5).each do |c|
      Certification.create(name: c, user_id: @edit_user.id)
    end if params['certifications'].present?
  end

end
