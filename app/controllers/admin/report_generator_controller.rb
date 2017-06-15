class Admin::ReportGeneratorController < AdminAreaController
  # before_action :current_user, :ensure_admin
  layout 'admin_area'

  def index
  end

  # def ensure_admin
  #     unless admin?
  #       redirect_to '/' and return
  #     end
  # end

  def show
  end
  
  def report1
  	@users = User.all

  	respond_to do |format|
  		attributes = %w{id name username email faculty created_at}
  		format.html
  		format.csv {send_data @users.to_csv(*attributes)}
  	end
  end


  def report2
  	@users = User.all

  	respond_to do |format|
  		attributes = %w{id username email gender faculty created_at updated_at}
  		format.html
  		format.csv {send_data @users.to_csv(*attributes)}
  	end
  end


end
