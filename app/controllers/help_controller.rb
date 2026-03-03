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
      MsrMailer.issue_email(
        @help.name,
        @help.email,
        @help.subject,
        @help.comments.to_plain_text,
        params[:share_email]
      ).deliver_later
    else
      flash[:alert] = 'An error occurred while receiving your issue.'
      render :show, status: :unprocessable_entity
    end
  rescue StandardError => e
    raise e unless Rails.env.production?

    flash[:alert] = 'An internal error occurred while receiving your issue.'
    render :show, status: :unprocessable_entity
  end
  
  private

  def help_params
    params.require(:help).permit(:name, :email, :subject, :comments)
  end
end
