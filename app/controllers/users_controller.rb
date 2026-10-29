# frozen_string_literal: true

class UsersController < SessionsController
  include TurnstileHelper
  
  skip_before_action :session_expiry, only: [:create]
  before_action :current_user,
                except: %i[
                  create
                  new
                  resend_confirmation
                  reset_password_confirmation
                  reset_password_form
                  unlock_account
                ]
  before_action :signed_in,
                except: %i[
                  new
                  create
                  show
                  resend_confirmation
                  confirm
                  reset_password_confirmation
                  reset_password_form
                  unlock_account
                ]

  LINK_EXPIRED_ALERT =
    'This link has expired or has already been used. Please request a new one.'

  def create
    @new_user = User.new(user_params)
    @new_user.pword = params[:user][:password] if @new_user.valid?

    if !verify_turnstile
      flash[:alert] = 'Captcha error, try again.'
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: {errors: 'captcha failure'}, status: :unprocessable_content }
      end 
    elsif @new_user.save
      hash = @new_user.generate_token_for(:email_confirmation)
      MsrMailer.confirmation_email(@new_user, hash).deliver_now
      
      respond_to do |format| 
        format.html do
          redirect_to root_path,
                      notice:
                      'Account has been created, please look in your emails to confirm your email address.'
        end
        format.json do
          render json:
                 'Account has been created, please look in your emails to confirm your email address.',
                 status: :unprocessable_content
        end
      end
    else
      respond_to do |format| 
        format.html { render 'new', status: :unprocessable_content }
        format.json do
          render json: @new_user.errors, status: :unprocessable_content
        end
      end
    end
  end

  def resend_confirmation
    email = params[:user][:email]
    user = User.find_by(email: email)
    if user.present?
      hash = user.generate_token_for(:email_confirmation)
      MsrMailer.confirmation_email(user, hash).deliver_now
      flash[:notice] = 'A new confirmation email has been sent'
    else
      flash[
        :alert
      ] = 'No users with that email were found. Please select a valid email.'
    end
    redirect_back(fallback_location: root_path)
  end

  def confirm
    user = User.find_by_token_for(:email_confirmation, params[:token])
    if user
      user.update(confirmed: true)
      MsrMailer.welcome_email(user).deliver_now
      flash[
        :notice
      ] = 'The email has been confirmed, you can now fully use your Makerepo Account !'
    else
      flash[:alert] = LINK_EXPIRED_ALERT
    end
    redirect_to root_path
  end

  def confirm_edited_email
    user, new_email = User.email_change_from_token(params[:token])
    if user.nil?
      flash[:alert] = LINK_EXPIRED_ALERT
    elsif user != @user
      flash[:alert] =
        'This link was requested by a different account. Please sign in as the account that requested the change.'
    elsif change_email_to(user, new_email)
      MsrMailer.email_changed_email(user, @old_email).deliver_now
      flash[:notice] = "The email has been updated to #{user.email} !"
    else
      flash[:alert] =
        'The email could not be updated, the address may already be used by another account. Please request a new change.'
    end
    redirect_to root_path
  end

  def unlock_account
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
    redirect_to root_path if signed_in?
    @new_user = User.new
  end

  def flag
    if params[:flagged_user].present? and params[:flag_message].present? and
         @user.staff?
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
    if params[:flagged_user].present? and @user.staff?
      @flagged_user = User.find(params[:flagged_user])
      @flagged_user.update(flagged: false, flag_message: nil)
      redirect_to user_path(@flagged_user.username) and return
    else
      redirect_to user_path(@user.username) and return
    end
  end

  def remove_flag
    redirect_to user_path(@user.username) and return unless @user.staff?

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
      flash[:alert] = 'Could not save changes. ' +
        @user.errors.full_messages.join('; ')
      redirect_to settings_profile_path
    end
  end

  def change_password
    if @user.pword != params[:user][:old_password]
      flash.now[:alert] = 'Incorrect old password.'
      render 'settings/admin', layout: 'setting' and return
    end

    if user_params[:password].blank?
      flash.now[:alert] = 'New password cannot be blank.'
      render 'settings/admin', layout: 'setting' and return
    end

    new_password = user_params[:password]
    if new_password != user_params[:password_confirmation]
      flash.now[:alert] = 'Your password and password confirmation do not match.'
      render 'settings/admin', layout: 'setting' and return
    end

    # The plaintext is checked (presence, strength); only the password columns are
    # then written, so an unrelated legacy-invalid field cannot block the change.
    if @user.plaintext_password_problems(new_password).any?
      render 'settings/admin', layout: 'setting' and return
    end

    begin
      @user.store_new_password!(new_password)
    rescue ActiveRecord::ActiveRecordError => e
      Rails.error.report(e, handled: true)
      @user.reload
      flash.now[:alert] = 'Your password could not be changed. Please try again.'
      render 'settings/admin', layout: 'setting' and return
    end

    session[:token_version] = @user.token_version if session[:user_id] # this session stays signed in
    MsrMailer.confirm_password_change(@user).deliver_now
    redirect_to settings_admin_path,
                notice:
                  'Password changed successfully, an email will be sent to confirm.'
  end

  def change_email
    if params[:new_email].present? and params[:confirm_new_email].present?
      if params[:new_email] == params[:confirm_new_email]
        if !User.find_by_email(params[:new_email]).present?
          MsrMailer.email_confirmation_email(
            params[:new_email],
            @user,
            @user.generate_email_change_token(params[:new_email])
          ).deliver_now
          flash[:notice] = 'A confirmation email has been sent to the new email'
        else
          flash[:alert] = 'This email is already used by a MakerRepo Account.'
        end
      else
        flash[:alert] = "This confirmation email isn't matching the new email"
      end
    else
      flash[
        :alert
      ] = 'There was a problem with the email, please try sending the email again.'
    end
    redirect_to settings_admin_path
  end

  def reset_password_form
    return if User.find_by_token_for(:password_reset, params[:token])

    flash[:alert] = LINK_EXPIRED_ALERT
    redirect_to forgot_password_path
  end

  def reset_password_confirmation
    user = User.find_by_token_for(:password_reset, params[:token])
    if user.nil?
      flash[:alert] = LINK_EXPIRED_ALERT
    elsif params[:password] != params[:password_confirmation]
      flash[:alert] = 'Your password and password confirmation do not match.'
    elsif (problems = user.plaintext_password_problems(params[:password])).any?
      # D-I14 for this action: the strength rules now see the plain password
      flash[:alert] = "Your password was not changed: #{problems.to_sentence}."
      return redirect_to reset_password_form_users_path(token: params[:token])
    else
      stored =
        begin
          user.store_new_password!(params[:password], clear_timed_lock: true)
          true
        rescue ActiveRecord::ActiveRecordError => e
          Rails.error.report(e, handled: true)
          false
        end
      if stored
        session[:token_version] = user.token_version if session[:user_id] == user.id
        MsrMailer.confirm_password_change(user).deliver_now
        flash[
          :notice
        ] = 'Your password has been updated, an email will be sent to confirm!'
      else
        flash[
          :alert
        ] = 'An error occured while trying to change your password. Please try again later or send us an email at uottawa.makerepo@gmail.com'
      end
    end
    redirect_to root_path
  end

  def change_programs
    user = User.find(params[:user_id])
    if user.present? && (@user.staff? || @user.admin?)
      begin
        programs = user.sync_programs!(
          development: params[:dev_program].present?,
          volunteer: params[:volunteer].present?,
          # JSON never removes teams (the React app does not send it)
          teams: params[:teams].present? || (json_request? ? nil : false)
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
        message = e.record.errors.full_messages.to_sentence.presence || e.message
        return render json: { error: message }, status: :unprocessable_content if json_request?

        flash[:alert] = "The programs could not be updated: #{message}"
        return redirect_to user_path(user.username)
      end
      if json_request?
        render json: { programs: programs }
        return
      end
      flash[:notice] = "The programs for #{user.name} has been updated!"
      redirect_to user_path(user.username)
    else
      if json_request?
        head :forbidden
        return
      end
      flash[
        :alert
      ] = 'An error occurred: A user must me selected; You need to be staff/admin to change the programs.'
      redirect_to root_path
    end
  end

  # Private repositories/makes on a profile are visible only to the profile
  # owner and admins (D-C59).
  def sees_private_repos?(repo_user)
    @user == repo_user || (@user && @user.admin?)
  end
  private :sees_private_repos?

  def show
    @repo_user =
      if @user.admin? || @user.staff?
        User.unscoped.find_by_username params[:username]
      else
        User.find_by_username params[:username]
      end

    raise ActiveRecord::RecordNotFound if @repo_user.nil?

    @programs = @repo_user.programs.pluck(:program_type)

    # Get repositories owned by user
    repo_scope = @repo_user.repositories.where(make_id: nil).order(created_at: :desc)
    repo_scope = repo_scope.public_repos unless sees_private_repos?(@repo_user)
    @pagy, @repositories = pagy(repo_scope, limit: 18)

    @acclaim_data = @repo_user.certifications
    
    makes_scope = @repo_user.repositories.includes(:owner, :photos).where.not(make_id: nil).order(created_at: :desc)
    makes_scope = makes_scope.public_repos unless sees_private_repos?(@repo_user)
    @pagy_makes, @makes = pagy(makes_scope, page_key: 'page_makes', limit: 18)

    @joined_projects = @repo_user.project_joins
    @photos = photo_hash
    @certifications = @repo_user.certifications.highest_level
    @skills = Skill.all
    @proficient_projects_awarded =
      proc do |training|
        training.proficient_projects.where(
          id: @repo_user.order_items.awarded.pluck(:proficient_project_id)
        )
      end
    @learning_modules_completed =
      proc do |training|
        training.learning_modules.where(
          id:
            @repo_user.learning_module_tracks.completed.pluck(
              :learning_module_id
            )
        )
      end
    @recomended_hours =
      proc do |training, levels|
        training.learning_modules.where(level: levels).count +
          training.proficient_projects.where(level: levels).count
      end
    @space_list = Space.all
    @staff_spaces = @repo_user.staff_spaces.pluck(:space_id)

    if @user.key_certification.nil? && @user.eql?(@repo_user) &&
         (
           @user.staff? ||
             @user.programs.pluck(:program_type).include?(Program::TEAMS)
         )
      key_cert = @user.build_key_certification
      key_cert.save
    end

    @keys_owned = @repo_user.keys
    @keys_supervising = Key.where(supervisor_id: @repo_user.id)
    @key_cert = @repo_user.key_certification

    @locker_rentals = @repo_user.locker_rentals

    respond_to do |format|
      format.html
      format.json do
        if @user.staff? || @user.admin? || @repo_user == @user
          render json: {
                   user: @repo_user.as_json(include: :rfid),
                   programs: @programs.as_json,
                   certifications: @certifications.as_json(include: :training)
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
    like_scope = Repository.where(id: repo_ids).order([sort_arr].to_h)

    if params[:category].present?
      category_name = SLUG_TO_CATEGORY_MODEL[params[:category]]
      like_scope = like_scope.includes(:categories).where(categories: { name: category_name })
    end

    @pagy, @repositories = pagy(like_scope, limit: 12)
    @photos = photo_hash
  end

  # Hard delete of the signed-in user's own account. Goes through the last-admin
  # guard: the last usable admin cannot delete themself.
  def destroy
    account = @user
    begin
      User.guarding_last_admin!([account.id]) do
        account.repositories.each(&:destroy)
        LabSession.where(user_id: account.id).destroy_all
        account.destroy!
      end
    rescue User::LastAdminError => e
      redirect_to user_path(account.username), alert: e.message
      return
    end
    sign_out
    redirect_to root_path
  end

  private

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
  def profile_params
    user_params.except(:password, :password_confirmation, :email)
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

  def sort_order
    case params[:sort]
    when 'newest'
      %i[created_at desc]
    when 'most_likes'
      %i[like desc]
    when 'most_makes'
      %i[make desc]
    when 'recently_updated'
      %i[updated_at desc]
    else
      %i[created_at desc]
    end
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

  def photo_hash
    repo = params[:show].eql?('makes') ? @makes : @repositories
    return {} if repo.blank?

    repository_ids = repo.map(&:id)
    photo_ids =
      Photo
        .where(repository_id: repository_ids)
        .group(:repository_id)
        .minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h, e| h.merge!(e.repository_id => e) }
  end
end
