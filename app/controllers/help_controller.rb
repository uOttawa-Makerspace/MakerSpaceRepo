class HelpController < SessionsController
  skip_before_action :session_expiry
  before_action :current_user

  layout 'help'

  def main; end

  def send_email
    @name = params[:name]
    @email = params[:email]
    @subject = params[:subject]
    @comments = params[:comments]
    @app_version = params[:app_version]
    MsrMailer.issue_email(@name, @email, @subject, @comments, @app_version).deliver_now
    respond_to do |format|
      format.html {
        flash[:notice] = 'Email successfully sent. You will be contacted soon.'
        redirect_to help_path
      }
      format.json {
        render json: {
          status: 'success'
        }
      }
    end
  end
end
