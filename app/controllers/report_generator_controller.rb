class ReportGeneratorController < AdminAreaController
  def index
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
