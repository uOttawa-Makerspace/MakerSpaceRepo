class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]
  
  layout 'admin_area'

  def index
    @edit_admin_users = User.all.order("created_at DESC").limit(10)
    @active_sessions = LabSession.where("sign_out_time > ?", Time.now).order("sign_in_time DESC")
    @active_users = Array.new
    @active_sessions.each do |session|
      @active_users.append(User.find(session.user_id))
    end
  end

  def search
    if !params[:q].blank?
      @query = params[:q]
      if params[:filter] == "Name"
        @edit_admin_users = User.where("LOWER(name) like LOWER(?)", "%#{@query}%")
      elsif params[:filter] == "Email"
        @edit_admin_users = User.where("LOWER(email) like LOWER(?)", "%#{@query}%")
      elsif params[:filter] == "Username"
        @edit_admin_users = User.where("LOWER(username) like LOWER(?)", "%#{@query}%")
      else
        @edit_admin_users = User.where('name like LOWER(?) OR email like LOWER(?) OR username like LOWER(?)', "%#{@query}%", "%#{@query}%", "%#{@query}%")
      end
    end
  end
  
  def show
    @all_sessions = @edit_admin_user.lab_sessions.order("sign_in_time DESC")
    each_session = 0
    count = 0
    @all_sessions.each do |session|
        if session.present?
          if session.sign_out_time < Time.now
            each_session = each_session + (session.sign_out_time - session.sign_in_time)/60
          else
            each_session = each_session + (Time.now - session.sign_in_time)/60
          end
          count = count + 1
        end
    end
    if count>0
      @average_time = (each_session/count).round
    else
      @average_time = each_session
    end
    @certifications = @edit_admin_user.certifications.order("lower(name) ASC")
  end

  def edit
    @rfids = Rfid.recent_unset
    @certifications = @edit_admin_user.certifications.order("lower(name) ASC")
  end

  def update
    @edit_admin_user.certifications.destroy_all
    @edit_admin_user.update!(user_params)
    if !params[:user][:rfid].blank? && rfid = Rfid.where("id = ?", params[:user][:rfid]).first
      if @edit_admin_user.rfid
        @edit_admin_user.rfid.destroy!
      end
      rfid.user = @edit_admin_user
      rfid.save!
    end
    if @edit_admin_user.update(user_params)
      create_certifications
      render json: { redirect_uri: "#{edit_admin_user_path(@edit_admin_user)}" }
      flash[:notice] = "User information updated!"
      
    end
  end

  private

  def user_params
    params.require(:user).permit(:gender, :faculty, :use, :role)
  end

  def load_user
    @edit_admin_user = User.find(params[:id])
  end
  
  def create_certifications
    params['certifications'].first(5).each do |c|
      Certification.create(name: c, user_id: @edit_admin_user.id)
    end if params['certifications'].present?
  end

end
