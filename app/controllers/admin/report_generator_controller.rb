class Admin::ReportGeneratorController < AdminAreaController

  layout 'admin_area'

  def index
  end

  def report1
  	@users = User.in_last_month

  	respond_to do |format|
  		attributes = %w{id name username email faculty program created_at}
  		format.html
  		format.csv {send_data @users.to_csv(*attributes)}
  	end
  end

  def report2
    @labs = LabSession.in_last_month
    column = []
    column << ["lab_id", "sign_in_time", "user_id", "name", "email", "faculty", "program"]             
    @labs.each do |lab|       
      row = []              
      row << lab.id << lab.sign_in_time       
      user = lab.user       
      row << lab.user.id << lab.user.name << lab.user.email << user.faculty << lab.user.program    
      column << row         
    end                                      
    respond_to do |format|
      format.html
      format.csv {send_data @labs.to_csv(column)}
    end
  end
end
