class HelpController < SessionsController

  skip_before_action :session_expiry
  before_action :current_user

  layout "help"

  def main
  end

  def send_email
    @name = params[:name]
    @email = params[:email]
    @subject = params[:subject]
    @comments = params[:comments]
    MsrMailer.issue_email(@name,@email,@subject,@comments).deliver_now
    flash[:notice] = "Email successfuly send. You will be contacted soon."
    redirect_to root_path
  end

end
