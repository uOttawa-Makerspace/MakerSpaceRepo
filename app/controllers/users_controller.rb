# frozen_string_literal: true

class UsersController < SessionsController
  skip_before_action :session_expiry, only: [:create]
  before_action :current_user, except: %i[create new resend_confirmation]
  before_action :signed_in, except: %i[new create show resend_confirmation confirm]

  def create
    @new_user = User.new(user_params)
    @new_user.pword = params[:user][:password] if @new_user.valid?

    respond_to do |format|
      if @new_user.save
        hash = Rails.application.message_verifier(:user).generate(@new_user.id)
        MsrMailer.confirmation_email(@new_user, hash).deliver_now
        format.html { redirect_to root_path, notice: "Account has been created, please look in your emails to confirm your email address." }
        format.json { render json: "Account has been created, please look in your emails to confirm your email address.", status: :unprocessable_entity }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @new_user.errors, status: :unprocessable_entity }
      end
    end
  end

  def resend_confirmation
    email = params[:user][:email]
    user = User.find_by(email: email)
    if user.present?
      hash = Rails.application.message_verifier(:user).generate(user.id)
      MsrMailer.confirmation_email(user, hash).deliver_now
      flash[:notice] = "A new confirmation email has been sent"
    else
      flash[:alert] = "No users with that email were found. Please select a valid email."
    end
    redirect_back(fallback_location: root_path)
  end

  def confirm
    @cc_token = params[:token]
    @verifier = Rails.application.message_verifier(:user)
    if @verifier.valid_message?(@cc_token)
      user_id = @verifier.verify(@cc_token)
      if User.find(user_id).present?
        user = User.find(user_id)
        user.update(confirmed: true)
        MsrMailer.welcome_email(user).deliver_now
        flash[:notice] = "The email has been confirmed, you can now fully use your Makerepo Account !"
      else
        flash[:alert] = "Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com"
      end
    else
      flash[:alert] = "Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com"
    end
    redirect_to root_path
  end

  def confirm_edited_email
    @user_token = params[:user_token]
    @user_verifier = Rails.application.message_verifier(:user)
    @email_token = params[:email_token]
    @email_verifier = Rails.application.message_verifier(:email)
    if @user_verifier.valid_message?(@user_token) and @email_verifier.valid_message?(@email_token)
      user_id = @user_verifier.verify(@user_token)
      new_email = @email_verifier.verify(@email_token)
      if User.find(user_id).present?
        user = User.find(user_id)
        old_email = user.email
        user.update(email: new_email)
        MsrMailer.email_changed_email(user, old_email).deliver_now
        flash[:notice] = "The email has been updated to #{user.email} !"
      else
        flash[:alert] = "Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com"
      end
    else
      flash[:alert] = "Something went wrong. Try to access the page again or send us an email at uottawa.makerepo@gmail.com"
    end
    redirect_to root_path
  end

  def new
    redirect_to root_path if signed_in?

    @new_user = User.new
  end

  def flag
    if params[:flag].present? and params[:flagged_user].present? and @user.staff?
      @flagged_user = User.find(params[:flagged_user])
      if params[:flag] == "flag" and params[:flag_message].present?
        @flagged_user.update(flagged: true, flag_message: params[:flag_message])
      elsif params[:flag] == "unflag"
        @flagged_user.update(flagged: false, flag_message: "")
      end
      redirect_to user_path(@flagged_user.username) and return
    else
      redirect_to user_path(@user.username) and return
    end
  end

  def remove_avatar
    @user.avatar.purge
    redirect_to settings_profile_path
  end

  def update
    if @user.update(user_params)
      flash[:notice] = 'Profile updated successfully.'
      redirect_to settings_profile_path
    else
      flash[:alert] = 'Could not save changes.'
      redirect_to settings_profile_path
    end
  end

  def change_password
    if github?
      @client = github_client
      @client_info = @client.user
    end

    if @user.pword != params[:user][:old_password]
      flash.now[:alert] = 'Incorrect old password.'
      render 'settings/admin', layout: 'setting' and return
    end

    if @user.update(user_params)
      @user.pword = @user.password
      @user.save
      redirect_to settings_admin_path, notice: 'Password changed successfully'
    else
      render 'settings/admin', layout: 'setting'
    end
  end

  def change_email
    if params[:new_email].present? and params[:confirm_new_email].present?
      if params[:new_email] == params[:confirm_new_email]
        if !User.find_by_email(params[:new_email]).present?
          user_hash = Rails.application.message_verifier(:user).generate(@user.id)
          email_hash = Rails.application.message_verifier(:email).generate(params[:new_email])
          MsrMailer.email_confirmation_email(params[:new_email], @user, user_hash, email_hash).deliver_now
          flash[:notice] = "A confirmation email has been sent to the new email"
        else
          flash[:alert] = "This email is already used by a MakerRepo Account."
        end
      else
        flash[:alert] = "This confirmation email isn't matching the new email"
      end
    else
      flash[:alert] = "There was a problem with the email, please try sending the email again."
    end
    redirect_to settings_admin_path
  end

  def show
    @repo_user = User.find_by username: params[:username]
    @github_username = Octokit::Client.new(access_token: @repo_user.access_token).login
    @repositories = if params[:username] == @user.username || @user.admin? || @user.staff?
                      @repo_user.repositories.where(make_id: nil).paginate(page: params[:page], per_page: 18)
                    else
                      @repo_user.repositories.public_repos.where(make_id: nil).paginate(page: params[:page], per_page: 18)
                    end

    @acclaim_badge_url = if params[:username] == @user.username
                           'https://www.youracclaim.com/earner/earned/share/'
                         else
                           'https://www.youracclaim.com/badges/'
                         end

    @acclaim_data = @repo_user.badges
    @makes = @repo_user.repositories.where.not(make_id: nil).page params[:page]
    @joined_projects = @user.project_joins
    @photos = photo_hash
    @certifications = @repo_user.certifications
    @remaining_trainings = @repo_user.remaining_trainings
  end

  def likes
    repo_ids = Like.where(user_id: @user.id).pluck(:repository_id)
    @repositories = Repository.order([sort_order].to_h).where(id: repo_ids).page params[:page]
    @photos = photo_hash
  end

  def destroy
    @user.destroy
    #disconnect_user
    redirect_to root_path
  end

  def vote # MAKE A UPVOTE CONTROLLER TO PUT THIS IN
    downvote = params['downvote'].eql?('t') ? true : false
    comment = Comment.find params[:comment_id]
    comment_user = comment.user
    if params[:voted].eql?('true')
      upvote = @user.upvotes.where(comment_id: comment.id).take
      if (!upvote.downvote && downvote) || (upvote.downvote && !downvote)
        upvote.update! downvote: downvote
        count = downvote ? comment.upvote - 2 : comment.upvote + 2
        downvote ? comment_user.decrement!(:reputation, 4) : comment_user.increment!(:reputation, 4)
        render json: { upvote_count: count, comment_id: comment.id, voted: 'true', color: '#19c1a5' }
      else
        upvote.destroy!
        count = downvote ? comment.upvote + 1 : comment.upvote - 1
        downvote ? comment_user.increment!(:reputation, 2) : comment_user.decrement!(:reputation, 2)
        render json: { upvote_count: count, comment_id: comment.id, voted: 'false', color: '#999' }
      end
    else
      @user.upvotes.create!(comment_id: comment.id, downvote: downvote)
      count = downvote ? comment.upvote - 1 : comment.upvote + 1
      downvote ? comment_user.decrement!(:reputation, 2) : comment_user.increment!(:reputation, 2)
      render json: { upvote_count: count, comment_id: comment.id, voted: 'true', color: '#19c1a5' }
    end
  rescue StandardError
    head 500
  end

  private

  def user_params
    params.require(:user).permit(:password, :password_confirmation, :url,
                                 :email, :name, :username, :avatar, :gender, :faculty, :use,
                                 :description, :terms_and_conditions, :program, :student_id, :how_heard_about_us,
                                 :year_of_study, :identity, :read_and_accepted_waiver_form)
  end

  def sort_order
    case params[:sort]
    when 'newest' then %i[created_at desc]
    when 'most_likes' then %i[like desc]
    when 'most_makes' then %i[make desc]
    when 'recently_updated' then %i[updated_at desc]
    else %i[created_at desc]
    end
  end

  def photo_hash
    repo = params[:show].eql?('makes') ? @makes : @repositories
    repository_ids = repo.map(&:id)
    photo_ids = Photo.where(repository_id: repository_ids).group(:repository_id).minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h, e| h.merge!(e.repository_id => e) }
  end
end
