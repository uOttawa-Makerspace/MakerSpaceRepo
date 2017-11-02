class Admin::UsersController < AdminAreaController
  before_action :load_user, only: [:show, :edit, :update]

  layout 'admin_area'

  def index
    if sort_params
      if params[:p] == "signed_in_users"
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "lab_sessions.sign_in_time"
          params[:direction] = "desc"
        end
        @users_temp = LabSession.joins(:user).where("sign_out_time > ?", Time.zone.now)
        if params[:location].present?
          @users_temp = @users_temp.joins("INNER JOIN pi_readers ON pi_mac_address = mac_address AND LOWER(pi_location) = LOWER('#{params[:location]}')")
        end
        @users_temp = @users_temp.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @users = @users_temp.includes(:user).map{|session| session.user}
        @total_pages = @users_temp.total_pages
      elsif params[:p] == "new_users" || !params[:p].present?
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "users.created_at"
          params[:direction] = "desc"
        end
        @users = User.includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @total_pages = @users.total_pages
      end
    else
      redirect_to admin_users_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def sort_params
    if (((["username","name","lab_sessions.sign_in_time","users.created_at"].include? params[:sort]) && (["desc","asc"].include? params[:direction])) || (!params[:sort].present? && !params[:direction].present?))
      return true
    end
  end

  def bulk_add_certifications
    if params['bulk_cert_users'].present? && params['bulk_certifications'].present?
      params['bulk_cert_users'].each do |user|
        if !User.find(user).certifications.where(name: params['bulk_certifications']).present?
          Certification.create(name: params['bulk_certifications'], user_id: user)
        end
      end
      redirect_to (:back)
      flash[:notice] = "Certifications added succesfully!"
    else
      redirect_to (:back)
      flash[:alert] = "Invalid parameters!"
    end
  end

  def search
    if sort_params
      if !params[:q].blank?
        @query = params[:q]
        if params[:filter] == "Name"
          @users = User.where("LOWER(name) like LOWER(?)", "%#{@query}%").includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        elsif params[:filter] == "Email"
          @users = User.where("LOWER(email) like LOWER(?)", "%#{@query}%").includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        elsif params[:filter] == "Username"
          @users = User.where("LOWER(username) like LOWER(?)", "%#{@query}%").includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        elsif !params[:filter].present?
          @users = User.where('LOWER(name) like LOWER(?) OR LOWER(email) like LOWER(?) OR LOWER(username) like LOWER(?)', "%#{@query}%", "%#{@query}%", "%#{@query}%").includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        end
      else
        redirect_to (:back)
        flash[:alert] = "Invalid parameters!"
      end
    else
      redirect_to admin_users_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def show
    @all_sessions = @edit_admin_user.lab_sessions.order("sign_in_time DESC")
    each_session = 0
    count = 0
    @all_sessions.each do |session|
        if session.present?
          if session.sign_out_time < Time.zone.now
            each_session = each_session + (session.sign_out_time - session.sign_in_time)/60
          else
            each_session = each_session + (Time.zone.now - session.sign_in_time)/60
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

  def delete_repository
    Repository.find(params[:id]).destroy
    redirect_to root_path
    flash[:notice] = "Repository Deleted!"
  end

  def delete_user
    User.find(params[:id]).destroy
    redirect_to root_path
    flash[:notice] = "User Deleted!"
  end

  def set_role
    @user = User.find(params[:id])
    @user.role = params[:role]
    @user.save
    redirect_to :back
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
