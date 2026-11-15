class HelpController < SessionsController
  include TurnstileHelper
  before_action :current_user

  HELP_FIELDS = %i[name email subject comments].freeze

  # send_email opens a GitHub issue per call; the React app sends no captcha, so it is rate limited
  rate_limit to: 5, within: 1.hour, only: :send_email, name: 'send-email',
             by: -> { current_user.id.presence || request.remote_ip },
             with: -> { render json: { error: 'Too many requests' }, status: :too_many_requests }

  # The web form never mails an address typed into it: guests' reports go to the team (the typed
  # address is only the Reply-To), signed-in users also get a copy at their account address.
  # It is rate limited per visitor.
  rate_limit to: 5, within: 1.hour, only: :create, name: 'create',
             by: -> { current_user.id.presence || request.remote_ip },
             with: -> {
               flash.now[:alert] = 'Too many requests, please try again later.'
               @help = Help.new(help_fields)
               render :show, status: :too_many_requests
             }

  def show
    @help = Help.new
  end

  # Saves the request and queues its filing job (HelpFilingJob mails the copies and opens the GitHub issue). The
  # request is recorded once the row is saved, so the user is told it was submitted even when the job cannot be
  # queued: Help#queue_filing reports that, and the sweep queues the job again.
  def create
    @help = Help.new(help_params.merge(user: (current_user if signed_in?), share_email: params[:share_email],
                                       source: Help::HELP_PAGE))

    unless verify_turnstile
      flash[:alert] = 'Captcha check failed, please try again.'
      render :show, status: :unprocessable_entity and return
    end

    if @help.save
      @help.queue_filing
      redirect_to help_path, notice: 'Your issue has been submitted.'
    else
      flash.now[:alert] = validation_message(@help, 'errors.help.not_received')
      render :show, status: :unprocessable_entity
    end
  rescue StandardError => e
    report_unexpected(e, source: 'help#create')
    flash.now[:alert] = unexpected_error_message
    render :show, status: :unprocessable_entity
  end


  # PUT /send_email: JSON endpoint used by the MakerRepo React app's Help form.
  # Never touches a user; same validations, filing job and support email as #create.
  # The confirmation always goes to the signed-in account: the posted name/email are
  # accepted (the React request shape) but ignored for addressing. Answers once the row is saved.
  def send_email
    unless signed_in?
      render json: { error: 'Authentication required' }, status: :unauthorized and return
    end

    attrs = params.slice(:subject, :comments).permit(:subject, :comments)
    @help = Help.new(attrs.merge(name: current_user.name, email: current_user.email, user: current_user,
                                 share_email: params[:share_email], app_version: params[:app_version].to_s.presence,
                                 source: Help::APP))

    if @help.save
      @help.queue_filing
      render json: { status: 'sent' }
    else
      render json: { errors: @help.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def help_params
    permit_help(params.require(:help))
  end

  def permit_help(fields)
    fields.permit(*HELP_FIELDS)
  end

  # The typed fields, for re-rendering the form (none when the request has no help param)
  def help_fields
    params[:help].is_a?(ActionController::Parameters) ? permit_help(params[:help]) : {}
  end
end
