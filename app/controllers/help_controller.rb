class HelpController < SessionsController
  include TurnstileHelper
  skip_before_action :session_expiry
  before_action :current_user

  def show
    @help = Help.new
  end

  def create
    @help = Help.new(help_params)
    @help.validate

    unless verify_turnstile
    end

    unless GithubIssuesService.new.create_issue(
             reporter: @help.name,
             title: @help.subject,
             body: @help.comments
           )
      flash[:alert] = 'An error occured while receiving your issue.'
      render :show
    end
  rescue StandardError => e
    raise e unless Rails.env.production?

    flash[:alert] = 'An error occured while receiving your issue.'
    render :show
  end

  def send_email
    @help = Help.new(params[:help])

    unless verify_turnstile
      respond_to do |format|
        format.html do
          redirect_to help_path,
                      alert:
                        'Please make sure you fill out the captcha correctly.'
        end
        format.json { render json: { status: 'error' }, status: :internal_server_error }
      end
    end

    unless @help.valid?
      flash[:alert] = 'Please fill in all fields'
      render 'main', status: :unprocessable_content
    end

    MsrMailer.issue_email(
      params[:help][:name],
      params[:help][:email],
      params[:help][:subject],
      params[:help][:comments],
      params[:app_version]
    ).deliver_later

    respond_to do |format|
      format.html do
        redirect_to help_path,
                    notice:
                      'Email successfully sent. You will be contacted soon.'
      end
      format.json { render json: { status: 'success' } }
    end
  end

  private

  def help_params
    params.require(:help).permit(:name, :email, :subject, :comments)
  end
end
