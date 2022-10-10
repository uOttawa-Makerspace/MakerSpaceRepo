class HelpController < SessionsController
  skip_before_action :session_expiry
  before_action :current_user

  layout "help"

  def main
    @help = Help.new
  end
  def send_email
    @help = Help.new(params[:help])
    if verify_recaptcha || params[:app_version].present?
      if !@help.valid?
        flash[:alert] = "Please fill in all fields"
        render "main", status: 422
      else
        @name = params[:help][:name]
        @email = params[:help][:email]
        @subject = params[:help][:subject]
        @comments = params[:help][:comments]
        @app_version = params[:app_version]
        MsrMailer.issue_email(
          @name,
          @email,
          @subject,
          @comments,
          @app_version
        ).deliver_now
        respond_to do |format|
          format.html do
            redirect_to help_path,
                        notice:
                          "Email successfully sent. You will be contacted soon."
          end
          format.json { render json: { status: "success" } }
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_to help_path,
                      alert:
                        "Please make sure you fill out the captcha correctly."
        end
        format.json { render json: { status: "error" } }
      end
    end
  end
end
