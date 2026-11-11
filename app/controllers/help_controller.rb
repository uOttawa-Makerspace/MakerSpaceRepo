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

  def create
    @help = Help.new(help_params)
    @help.defang_github_text = true # the GitHub issue is public

    unless verify_turnstile
      flash[:alert] = 'Captcha check failed, please try again.'
      render :show, status: :unprocessable_entity and return
    end

    if @help.save && @help.file_issue
      redirect_to help_path, flash_for_copy(queue_issue_copy)
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
  # Never touches a user; same validations, GitHub issue and support email as #create.
  # The confirmation always goes to the signed-in account: the posted name/email are
  # accepted (the React request shape) but ignored for addressing.
  def send_email
    unless signed_in?
      render json: { error: 'Authentication required' }, status: :unauthorized and return
    end

    attrs = params.slice(:subject, :comments).permit(:subject, :comments)
    @help = Help.new(attrs.merge(name: current_user.name, email: current_user.email))
    @help.defang_github_text = true # the GitHub issue is public

    if @help.save && @help.file_issue
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

  # Queues the copy of the report that goes by email. The report is already saved, so a queue
  # failure is reported and the user is told the copy will not arrive; it is not an error page.
  def queue_issue_copy
    text = @help.comments.to_plain_text
    if signed_in?
      # Signed in: the copy goes to the account's own address (bcc the team), never the typed one
      MsrMailer.issue_email(@help.name, current_user.email, @help.subject, text, params[:share_email],
                            contact_email: @help.email, account: current_user).deliver_later
    else
      MsrMailer.issue_email_to_team(@help.name, @help.email, @help.subject, text,
                                    via: 'the MakerRepo help page').deliver_later
    end
    true
  rescue ActiveJob::EnqueueError, ActiveRecord::ActiveRecordError => e
    report_unexpected(e, source: 'help#create')
    false
  end

  def flash_for_copy(queued)
    queued ? { notice: 'Your issue has been submitted.' } : { alert: I18n.t('errors.help.copy_not_sent') }
  end

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
