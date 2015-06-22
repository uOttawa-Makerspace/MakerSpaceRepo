class StaticPagesController < SessionsController

  before_action :current_user
  
  def home
  end

  def about
  end

  def contact
  end

  def report_repository
  	repository = Repository.find params[:repository_id]
  	MsrMailer.repo_report(repository).deliver
  	flash[:notice] = "Repository has been reported"
  	redirect_to request.referrer
  end
  
end
