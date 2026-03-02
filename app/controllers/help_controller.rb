class HelpController < SessionsController
  include TurnstileHelper
  skip_before_action :session_expiry
  before_action :current_user

  def show
    @help = Help.new
  end

  def create
    @help = Help.new(help_params)

    unless verify_turnstile
      flash[:alert] = 'Captcha check failed, please try again.'
      render :show, status: :unprocessable_entity and return
    end

    if @help.save
      redirect_to help_path, notice: 'Your issue has been submitted.'
    else
      flash[:alert] = 'An error occurred while receiving your issue.'
      render :show, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise e unless Rails.env.production?

    flash[:alert] = 'An error occurred while receiving your issue.'
    render :show, status: :unprocessable_entity
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
        format.json do
          render json: { status: 'error' }, status: :internal_server_error
        end
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
