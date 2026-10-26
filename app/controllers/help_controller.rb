class HelpController < SessionsController
  include TurnstileHelper
  skip_before_action :session_expiry
  before_action :current_user

  # send_email opens a public GitHub issue per call and has no captcha (React app)
  rate_limit to: 5, within: 1.hour, only: :send_email,
             by: -> { current_user.id.presence || request.remote_ip },
             with: -> { render json: { error: 'Too many requests' }, status: :too_many_requests }

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
  
  # PUT /send_email: JSON endpoint used by the MakerRepo React app's Help form.
  # Never touches a user; same validations, GitHub issue and support email as #create.
  # The confirmation always goes to the signed-in account: the posted name/email are
  # accepted (the React request shape) but ignored for addressing.
  def send_email
    unless signed_in?
      render json: { error: 'Authentication required' }, status: :unauthorized and return
    end

    attrs = params.slice(:subject, :comments).permit(:subject, :comments)
    @help = Help.new(attrs.merge(name: current_user.name, email: current_user.email))

    if @help.save
      MsrMailer.issue_email(
        @help.name,
        @help.email,
        @help.subject,
        @help.comments.to_plain_text,
        params[:share_email],
        params[:app_version].to_s.presence
      ).deliver_later
      render json: { status: 'sent' }
    else
      render json: { errors: @help.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def help_params
    params.require(:help).permit(:name, :email, :subject, :comments)
  end
end
