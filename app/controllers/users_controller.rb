# frozen_string_literal: true

class UsersController < SessionsController
  include TurnstileHelper
  include RepositorySorting
  
  before_action :current_user,
                except: %i[
                  create
                  new
                  resend_confirmation
                  send_confirmation
                  reset_password_confirmation
                  reset_password_form
                  unlock_account
                  apply_unlock
                ]
  before_action :signed_in,
                except: %i[
                  new
                  create
                  show
                  resend_confirmation
                  send_confirmation
                  confirm
                  apply_confirmation
                  reset_password_confirmation
                  reset_password_form
                  unlock_account
                  apply_unlock
                ]

  before_action :ensure_staff, only: %i[flag unflag remove_flag change_programs]

  # Re-authentication (the current password on change_password / change_email) is throttled
  # per signed-in user, one budget shared with every other re-check (see ReauthThrottle).
  include ReauthThrottle
  before_action :limit_reauth_attempts, only: %i[change_password change_email], if: :current_password_submitted?

  LINK_EXPIRED_ALERT =
    'This link has expired or has already been used. Please request a new one.'
  RESET_LINK_INVALID_ALERT =
    'Your reset link is no longer valid. Please sign in or request a new link.'
  EMAIL_CHANGE_OTHER_ACCOUNT_ALERT =
    'This link was requested by a different account. Please sign in as the account that requested the change.'

  SIGN_UP_THROTTLED_MESSAGE = 'Too many sign-up attempts, please try again later.'

  before_action :refuse_when_signed_in, only: %i[new create]

  rate_limit(**StaticPagesController::RESET_PASSWORD_RATE_LIMIT, only: :reset_password_confirmation,
                                                                with: -> { reset_password_throttled })

  rate_limit to: 30, within: 1.hour, only: :create, name: 'sign-up-ip',
             by: -> { request.remote_ip }, with: -> { sign_up_throttled }

  # The new account keeps the language the sign-up page was shown in (always a supported one, see RequestLocale),
  # so its confirmation and welcome mails are written in it.
  def create
    @new_user = User.new(user_params.merge(locale: I18n.locale.to_s))
    hash_sign_up_password if @new_user.valid?

    if !verify_turnstile
      flash[:alert] = 'Captcha error, try again.'
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: {errors: 'captcha failure'}, status: :unprocessable_content }
      end 
    elsif @new_user.only_email_taken?
      answer_taken_email_sign_up
    else
      create_account_or_show_errors
    end
  end

  # The answer is the same whether or not the email belongs to an account (and when the
  # request is rate limited); only an account that is still unconfirmed is mailed.
  RESEND_CONFIRMATION_NOTICE =
    'If that email belongs to an account that still needs confirming, a confirmation email has been sent.'

  rate_limit to: 30, within: 1.hour, only: :send_confirmation, name: 'resend-ip',
             by: -> { request.remote_ip }, with: -> { resend_confirmation_response }

  # GET: asks for confirmation before anything is sent, so opening the link
  # (or having it prefetched) never mails anyone.
  def resend_confirmation
    @email = resend_confirmation_email
    redirect_to resend_email_confirmation_path if @email.blank?
  end

  # POST: sends the mail.
  def send_confirmation
    email = resend_confirmation_email
    user = User.find_by(email: email) if email.present?
    if user && !user.confirmed? && mail_budget_left?('resend', email)
      hash = user.generate_token_for(:email_confirmation)
      MsrMailer.confirmation_email(user, hash).deliver_later
    end
    resend_confirmation_response
  end

  # GET, the link in the sign-up mail: shows a button that POSTs the token to
  # apply_confirmation. A GET never changes anything.
  def confirm
    return if User.find_by_token_for(:email_confirmation, params[:token])

    flash[:alert] = LINK_EXPIRED_ALERT
    redirect_to root_path
  end

  # POST /confirm
  def apply_confirmation
    user = User.find_by_token_for(:email_confirmation, params[:token])
    if user
      user.confirm_email!
      MsrMailer.welcome_email(user).deliver_now
      flash[
        :notice
      ] = 'The email has been confirmed, you can now fully use your Makerepo Account !'
    else
      flash[:alert] = LINK_EXPIRED_ALERT
    end
    redirect_to root_path
  end

  # GET, the link in the confirmation email: shows what would change and a button
  # that POSTs the token to apply_edited_email. A GET never changes anything, so
  # a cross-site navigation to the link cannot apply it.
  def confirm_edited_email
    user, @new_email = User.email_change_from_token(params[:token])
    return redirect_to(root_path) unless email_change_token_for_current_user?(user)

    @token = params[:token]
  end

  # POST /confirm_edited_email: applies the change for the signed-in owner of the
  # token. The token is bound to the address it was issued for (and the account's
  # token_version), so it is refused once the address has changed.
  def apply_edited_email
    user, new_email = User.email_change_from_token(params[:token])
    if !email_change_token_for_current_user?(user)
      nil # the alert is set
    elsif change_email_to(user, new_email)
      MsrMailer.email_changed_email(user, @old_email).deliver_now
      flash[:notice] = "The email has been updated to #{user.email} !"
    else
      flash[:alert] = email_update_failure_alert(user)
    end
    redirect_to root_path
  end

  # GET, the link in the unlock mail: shows a button that POSTs the token to
  # apply_unlock. A GET never changes anything.
  def unlock_account
    return if User.unlock_link_valid?(params[:token])

    flash[:alert] = LINK_EXPIRED_ALERT
    redirect_to root_path
  end

  # POST /unlock_account
  def apply_unlock
    user = User.find_by_token_for(:account_unlock, params[:token])
    if user
      user.update_columns(locked: false, auth_attempts: 0, locked_until: nil)
      flash[:notice] = 'The account has been unlocked!'
    else
      flash[:alert] = LINK_EXPIRED_ALERT
    end
    redirect_to root_path
  end

  def search
    search_results = if current_user.staff?
                       User.fuzzy_search(params[:search]).as_json(only: %i[name username])
                     else
                       User.reduced_fuzzy_search(params[:search]).as_json(only: :username)
                     end
    render json: { users: search_results }
  end

  def new
    @new_user = User.new
  end

  def flag
    if params[:flagged_user].present? and params[:flag_message].present?
      @flagged_user = User.find(params[:flagged_user])
      @flagged_user.flagged = true

      if @flagged_user.flag_message.blank?
        @flagged_user.flag_message = "; #{params[:flag_message]}"
      else
        @flagged_user.flag_message += "; #{params[:flag_message]}"
      end

      @flagged_user.save
      redirect_to user_path(@flagged_user.username) and return
    else
      redirect_to user_path(@user.username) and return
    end
  end

  def unflag
    if params[:flagged_user].present?
      @flagged_user = User.find(params[:flagged_user])
      @flagged_user.update(flagged: false, flag_message: nil)
      redirect_to user_path(@flagged_user.username) and return
    else
      redirect_to user_path(@user.username) and return
    end
  end

  def remove_flag
    @repo_user = User.find(params[:repo_user_id])
    msg = params[:flag_msg]
    @repo_user.flag_message = @repo_user.flag_message.gsub("; #{msg}", '')
    @repo_user.flagged = (@repo_user.flag_message.blank? ? false : true)
    @repo_user.save
    redirect_to user_path(@repo_user.username)
  end

  def remove_avatar
    @user.avatar.purge
    redirect_to settings_profile_path
  end

  def update
    if @user.update(profile_params)
      flash[:notice] = 'Profile updated successfully.'
      redirect_to settings_profile_path
    else
      flash[:alert] = validation_message(@user, "failed_saves.profile")
      redirect_to settings_profile_path
    end
  end

  def change_password
    if (alert = change_password_alert)
      flash.now[:alert] = alert
      render_password_settings
    # The plaintext is checked (presence, strength); only the password columns are
    # then written, so an unrelated legacy-invalid field cannot block the change.
    elsif @user.plaintext_password_problems(user_params[:password]).any?
      render_password_settings
    else
      store_changed_password(user_params[:password])
    end
  end

  # POST only, and it needs the account's current password (the same check as
  # change_password, throttled by limit_reauth_attempts): the token it mails confirms the
  # change of address.
  def change_email
    if (alert = current_password_alert)
      redirect_to settings_admin_path, alert: alert
      return
    end

    if params[:new_email].present? and params[:confirm_new_email].present?
      if params[:new_email] != params[:confirm_new_email]
        flash[:alert] = "This confirmation email isn't matching the new email"
      elsif (shape_error = User.email_shape_error(params[:new_email]))
        flash[:alert] = shape_error
      elsif User.find_by_email(params[:new_email]).present?
        flash[:alert] = 'This email is already used by a MakerRepo Account.'
      else
        MsrMailer.email_confirmation_email(
          params[:new_email],
          @user,
          @user.generate_email_change_token(params[:new_email])
        ).deliver_now
        flash[:notice] = 'A confirmation email has been sent to the new email'
      end
    else
      flash[
        :alert
      ] = 'There was a problem with the email, please try sending the email again.'
    end
    redirect_to settings_admin_path
  end

  def reset_password_form
    return if User.password_reset_link_valid?(params[:token])

    flash[:alert] = LINK_EXPIRED_ALERT
    redirect_to forgot_password_path
  end

  def reset_password_confirmation
    user = User.find_by_token_for(:password_reset, params[:token])
    if (alert = reset_password_alert(user))
      flash[:alert] = alert
      redirect_to root_path
    elsif (problems = user.plaintext_password_problems(params[:password])).any?
      # the strength rules see the plain password
      # A problem may already end its sentence with a full stop (the blank message does).
      flash[:alert] = "#{t('errors.users.password_not_changed')} #{problems.to_sentence.delete_suffix('.')}."
      redirect_to reset_password_form_users_path(token: params[:token])
    else
      store_reset_password(user)
    end
  end

  def change_programs
    user = User.find(params[:user_id])
    begin
      programs = user.sync_programs!(
        development: params[:dev_program].present?,
        volunteer: params[:volunteer].present?,
        # JSON never removes teams (the React app does not send it)
        teams: params[:teams].present? || (json_request? ? nil : false)
      )
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
      message = validation_message(e.record, 'errors.users.programs_not_updated')
      return render json: { error: message }, status: :unprocessable_content if json_request?

      flash[:alert] = message
      return redirect_to user_path(user.username)
    end
    if json_request?
      render json: { programs: programs }
      return
    end
    flash[:notice] = "The programs for #{user.name} has been updated!"
    redirect_to user_path(user.username)
  end

  # Private repositories/makes on a profile are visible only to the profile
  # owner, staff and admins (staff? includes admin).
  def sees_private_repos?(repo_user)
    @user == repo_user || (@user && @user.staff?)
  end
  private :sees_private_repos?

  def show
    # A deleted account's profile is shown to admins only (like its badges).
    @repo_user =
      if @user.admin?
        User.unscoped.find_by_username params[:username]
      else
        User.find_by_username params[:username]
      end

    raise ActiveRecord::RecordNotFound if @repo_user.nil?

    @programs = @repo_user.programs.pluck(:program_type)

    # Get repositories owned by user
    repo_scope = @repo_user.repositories.with_card_data.where(make_id: nil).order(created_at: :desc)
    repo_scope = repo_scope.public_repos unless sees_private_repos?(@repo_user)
    @pagy, @repositories = pagy(repo_scope, limit: 18)

    @acclaim_data = @repo_user.certifications_with_training
    
    makes_scope = @repo_user.repositories.with_card_data.where.not(make_id: nil).order(created_at: :desc)
    makes_scope = makes_scope.public_repos unless sees_private_repos?(@repo_user)
    @pagy_makes, @makes = pagy(makes_scope, page_key: 'page_makes', limit: 18)

    @joined_projects = joined_projects_of(@repo_user)
    @certifications = @repo_user.certifications.highest_level
    @skills = Skill.includes(trainings: %i[proficient_projects learning_modules])
    if @user.key_certification.nil? && @user.eql?(@repo_user) &&
         (
           @user.staff? ||
             @user.programs.pluck(:program_type).include?(Program::TEAMS)
         )
      key_cert = @user.build_key_certification
      key_cert.save
    end

    load_private_profile_sections

    respond_to do |format|
      format.html
      format.json do
        if @user.staff? || @user.admin? || @repo_user == @user
          render json: {
                   user: @repo_user.as_json(include: :rfid),
                   programs: @programs.as_json,
                   certifications: @certifications.as_json(include: :training, except: :share_token)
                 }
        else
          head :unauthorized
        end
      end
    end
  end

  def likes
    sort_arr = sort_order
    repo_ids = Like.where(user_id: @user.id).pluck(:repository_id)
    like_scope = Repository.viewable_by(@user, authorized_repo_ids).with_card_data.where(id: repo_ids).order([sort_arr].to_h)

    like_scope = in_requested_categories(like_scope) if params[:category].present?
    @category_slug = params[:category] if SLUG_TO_CATEGORY_MODEL.key?(params[:category])

    @pagy, @repositories = pagy(like_scope, limit: 12)
  end

  private

  # The user's project joins. The joined projects tab lists each one's proposal with its author and photos, read
  # together; the other tabs do not list them.
  def joined_projects_of(user)
    return user.project_joins unless params[:show] == 'projects_assigned'

    user.project_joins.includes(project_proposal: [:user, { photos_attachments: :blob }])
  end

  # Each private section is loaded only for a viewer who may see it.
  def load_private_profile_sections
    if @repo_user.roles_visible_to?(@user)
      @space_list = Space.all
      @staff_spaces = @repo_user.staff_spaces.pluck(:space_id)
    end
    if @repo_user.keys_visible_to?(@user)
      @keys_owned = @repo_user.keys
      @keys_supervising = Key.where(supervisor_id: @repo_user.id)
    end
    @key_cert = @repo_user.key_certification if @repo_user.key_certification_visible_to?(@user)
    @locker_rentals = @repo_user.locker_rentals if @repo_user.lockers_visible_to?(@user)
  end

  def ensure_staff
    return if @user.staff?

    if json_request?
      head :forbidden
    else
      redirect_to root_path, alert: I18n.t('errors.users.staff_only')
    end
  end

  # Keeps the repositories filed under the requested category slugs (one slug or a list). Slugs that are
  # not text or not known are ignored; when none is known the result is empty.
  def in_requested_categories(scope)
    names = Array.wrap(params[:category]).grep(String).filter_map { |slug| SLUG_TO_CATEGORY_MODEL[slug] }
    return scope.none if names.empty?

    scope.includes(:categories).where(categories: { name: names })
  end

  # The normalised email, or '' when none was given or it is longer than an address can be.
  def resend_confirmation_email
    fields = params[:user]
    email = fields.is_a?(ActionController::Parameters) ? fields[:email].to_s.strip.downcase : ''
    email.length > 254 ? '' : email
  end

  # Registering is for guests: a signed-in visitor is sent home (JSON clients get a 403).
  def refuse_when_signed_in
    return unless signed_in?

    message = I18n.t('sessions.already_signed_in')
    respond_to do |format|
      format.html { redirect_to root_path, alert: message }
      format.json { render json: { error: message }, status: :forbidden }
    end
  end

  # The visitor is answered as for a real sign-up, and the same password hashing is done so the
  # answer takes as long. Nothing is saved; the owner of a live account is told by mail.
  def answer_taken_email_sign_up
    hash_sign_up_password
    notify_existing_account_of_sign_up(@new_user.email)
    sign_up_accepted_response
  end

  # The password is hashed once per request, whichever way the sign-up goes.
  def hash_sign_up_password
    return if @sign_up_password_hashed

    @new_user.pword = params[:user][:password]
    @sign_up_password_hashed = true
  end

  def create_account_or_show_errors
    saved = @new_user.save_unless_email_taken
    return answer_taken_email_sign_up if saved.nil?
    return accept_new_account if saved

    # Whether an address already has an account is never told to the visitor. An address
    # taken since the first check leaves nothing else to report.
    @new_user.errors.delete(:email, :taken)
    return answer_taken_email_sign_up if @new_user.errors.empty?

    respond_to do |format|
      format.html { render 'new', status: :unprocessable_content }
      format.json { render json: @new_user.errors, status: :unprocessable_content }
    end
  end

  def accept_new_account
    hash = @new_user.generate_token_for(:email_confirmation)
    MsrMailer.confirmation_email(@new_user, hash).deliver_later
    sign_up_accepted_response
  end

  def sign_up_accepted_response
    message = I18n.t('sessions.account_created')
    respond_to do |format|
      format.html { redirect_to root_path, notice: message }
      format.json { render json: { message: message }, status: :created }
    end
  end

  # Tells the owner of an existing account that someone tried to sign up with their address.
  # At most MAIL_PER_ADDRESS_LIMIT such mails an hour per address; the visitor's answer is the same either way.
  def notify_existing_account_of_sign_up(email)
    return unless mail_budget_left?('sign-up-attempt', email)

    MsrMailer.sign_up_attempt_email(email).deliver_later
  end

  def sign_up_throttled
    respond_to do |format|
      format.html { redirect_to root_path, alert: SIGN_UP_THROTTLED_MESSAGE }
      format.json { render json: { error: SIGN_UP_THROTTLED_MESSAGE }, status: :too_many_requests }
    end
  end

  def resend_confirmation_response
    flash[:notice] = RESEND_CONFIRMATION_NOTICE
    redirect_back(fallback_location: root_path)
  end

  # The current password the action was given (change_password nests it).
  def submitted_current_password
    (action_name == 'change_password' ? params.dig(:user, :old_password) : params[:current_password]).to_s
  end

  def render_password_settings
    render 'settings/admin', layout: 'setting'
  end

  # The first refusal of a password change, in order: the current password (which
  # current_password_alert verifies), a blank new one, a confirmation mismatch.
  def change_password_alert
    current_password_alert || new_password_alert
  end

  def new_password_alert
    return 'New password cannot be blank.' if user_params[:password].blank?

    'Your password and password confirmation do not match.' if user_params[:password] != user_params[:password_confirmation]
  end

  def store_changed_password(new_password)
    # A timed (brute-force) lockout is cleared: the owner just proved the password.
    @user.store_new_password!(new_password, clear_timed_lock: true)
  rescue ActiveRecord::StaleObjectError
    # An expected race, not an error: the credentials were revoked while this request
    # ran (or the account was soft-deleted or removed). This session is dead, never
    # re-synced.
    sign_out
    redirect_to login_path, alert: 'Your session has ended. Please sign in again.'
  rescue ActiveRecord::ActiveRecordError => e
    report_unexpected(e, source: 'users#update_password')
    flash.now[:alert] = I18n.t('errors.users.password_not_saved', reference: error_reference)
    render_password_settings
  else
    session[:token_version] = @user.token_version if session[:user_id] # this session stays signed in
    MsrMailer.confirm_password_change(@user).deliver_now
    redirect_to settings_admin_path,
                notice:
                  'Password changed successfully, an email will be sent to confirm.'
  end

  # The answer of a throttled reset request (StaticPagesController#reset_password).
  def reset_password_throttled
    flash.now[:notice] = StaticPagesController::RESET_PASSWORD_NOTICE
    render 'static_pages/forgot_password'
  end

  # The refusal of a password reset before its strength check: a link that does not
  # resolve, then a confirmation mismatch.
  def reset_password_alert(user)
    return LINK_EXPIRED_ALERT if user.nil?

    'Your password and password confirmation do not match.' if params[:password] != params[:password_confirmation]
  end

  def store_reset_password(user)
    user.store_new_password!(params[:password], clear_timed_lock: true)
  rescue ActiveRecord::StaleObjectError
    redirect_after_reset_race
  rescue ActiveRecord::ActiveRecordError => e
    report_unexpected(e, source: 'users#reset_password')
    flash[:alert] = I18n.t('errors.users.password_not_saved', reference: error_reference)
    redirect_to root_path
  else
    session[:token_version] = user.token_version if session[:user_id] == user.id
    MsrMailer.confirm_password_change(user).deliver_now
    flash[
      :notice
    ] = 'Your password has been updated, an email will be sent to confirm!'
    redirect_to root_path
  end

  # A concurrent bump (an expected race, not an error). Re-check UNCACHED: the
  # request's query cache may hold the first lookup. A link that no longer resolves
  # can mean a changed password, a soft-deleted account or an expiry, which must
  # not be told apart to someone holding no valid token: one neutral message.
  def redirect_after_reset_race
    if User.uncached { User.find_by_token_for(:password_reset, params[:token]) }.nil?
      flash[:alert] = RESET_LINK_INVALID_ALERT
      redirect_to login_path
    else
      flash[:alert] = 'Your account changed while resetting the password. Please use the link again.'
      redirect_to reset_password_form_users_path(token: params[:token])
    end
  end

  # nil when the submitted current password is right (which clears the attempt
  # count); the alert otherwise. The attempt was counted by limit_reauth_attempts.
  def current_password_alert
    return 'Please enter your current password.' unless current_password_submitted?

    if @user.authenticate_password(submitted_current_password)
      RateLimitCounter.reset(@user.reauth_attempts_key)
      nil
    else
      'Incorrect current password.'
    end
  end

  # A live email-change token whose user is the signed-in user; sets the alert
  # otherwise.
  def email_change_token_for_current_user?(user)
    alert = if user.nil?
              LINK_EXPIRED_ALERT
            elsif user != @user
              EMAIL_CHANGE_OTHER_ACCOUNT_ALERT
            end
    flash[:alert] = alert if alert
    alert.nil?
  end

  # The validation error when the address itself was refused, otherwise the
  # address was taken by another account in the meantime.
  def email_update_failure_alert(user)
    reason = user.errors.full_messages_for(:email).to_sentence.presence ||
             'the address may already be used by another account'
    "The email could not be updated: #{reason}. Please request a new change."
  end

  # Applies the address; false (nothing changed) when it is rejected, e.g. taken
  # by another account in the meantime. Remembers the previous address.
  def change_email_to(user, new_email)
    @old_email = user.email
    user.update(email: new_email)
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def json_request?
    request.format.json? || request.content_mime_type&.json?
  end

  # Profile edits: no :email (use change_email's confirm flow) and no :password
  # (use change_password).
  # Renaming an account is admin-only, so :username is not editable here. The waiver
  # checkbox is on the profile form for an account that never accepted it: it can be
  # accepted here, never withdrawn.
  def profile_params
    permitted = user_params.except(:password, :password_confirmation, :email, :username)
    accepting = ActiveModel::Type::Boolean.new.cast(permitted[:read_and_accepted_waiver_form]) == true
    permitted = permitted.except(:read_and_accepted_waiver_form) if @user.read_and_accepted_waiver_form || !accepting
    permitted
  end

  def user_params
    params.require(:user).permit(
      :password,
      :password_confirmation,
      :url,
      :email,
      :name,
      :username,
      :avatar,
      :gender,
      :faculty,
      :use,
      :description,
      :terms_and_conditions,
      :program,
      :how_heard_about_us,
      :year_of_study,
      :identity,
      :student_id,
      :read_and_accepted_waiver_form
    )
  end

  SLUG_TO_CATEGORY_MODEL = {
    'internet-of-things' => 'Internet of Things',
    'course-related-projects' => 'Course-related Projects',
    'gng2101/gng2501' => 'GNG2101/GNG2501',
    'gng1103/gng1503' => 'GNG1103/GNG1503',
    'health-sciences' => 'Health Sciences',
    'wearable' => 'Wearable',
    'mobile-development' => 'Mobile Development',
    'virtual-reality' => 'Virtual Reality',
    'other-projects' => 'Other Projects',
    'uottawa-team-projects' => 'uOttawa Team Projects'
  }.freeze
end
