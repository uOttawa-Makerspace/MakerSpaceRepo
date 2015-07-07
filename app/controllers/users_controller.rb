class UsersController < SessionsController

  skip_before_action :session_expiry, only: [:create]
  before_action :current_user, except: [:create, :new]
  before_action :signed_in, except: [:new, :create, :show]
    
  def create
    @new_user = User.new(user_params)
    @new_user.pword = params[:user][:password] if @new_user.valid?
    
    respond_to do |format|
      if @new_user.save
        session[:user_id], cookies[:user_id] = @new_user.id, @new_user.id
        format.html { redirect_to root_path }
        format.json { render json: { success: @user.id }, status: :ok }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @user.errors, status: :unprocessable_entity }
      end
    end
  end

  def new
    return redirect_to root_path if signed_in?
    @new_user = User.new
   end

  def update
    if @user.update(user_params)
      redirect_to settings_profile_path
    else
      render 'edit', alert: 'Something went wrong!'
    end
  end

  def change_password
      flag = false

      if @user.pword == params[:old_password] and
        params[:user][:password] == params[:user][:password_confirmation] then
          @user.pword = params[:user][:password]
          flag = true
      end

      if flag
        @user.save
        redirect_to action: :account_setting, notice: 'Password changed successfully'
      else
        render :account_setting, alert: 'Something went wrong!', layout: "setting"
      end
  end

  def show
    @repo_user = User.find_by username: params[:username]
    @github_username = Octokit::Client.new(access_token: @repo_user.access_token).login
    @repositories = @repo_user.repositories.where(make_id: nil).page params[:page]
    @makes = @repo_user.repositories.where.not(make_id: nil).page params[:page]

    # @repositories = @repo_user.repositories.page params[:page]
  end

  def likes
    repo_ids = Like.where(user_id: @user.id).pluck(:repository_id)
    @repositories = Repository.order([sort_order].to_h).where(id: repo_ids).page params[:page]
    @photos = photo_hash
  end

  def destroy
    @user.destroy
    disconnect_user
    redirect_to root_path
  end

  def vote # MAKE A UPVOTE CONTROLLER TO PUT THIS IN
    downvote = if params['downvote'].eql?('t') then true else false end
    comment = Comment.find params[:comment_id]
    if params[:voted].eql?('true')
      upvote = @user.upvotes.where(comment_id: comment.id).take
      if (!upvote.downvote && downvote) || (upvote.downvote && !downvote)
        upvote.update! downvote: downvote
        count = downvote ? comment.upvote - 2 : comment.upvote + 2
        render json: { upvote_count: count, comment_id: comment.id, voted: 'true', color: '#19c1a5' }
      else
        upvote.destroy!
        count = downvote ? comment.upvote + 1 : comment.upvote - 1
        render json: { upvote_count: count, comment_id: comment.id, voted: 'false', color: '#999' }
      end
    else
      @user.upvotes.create!(comment_id: comment.id, downvote: downvote)
      count = downvote ? comment.upvote - 1 : comment.upvote + 1
      render json: { upvote_count: count, comment_id: comment.id, voted: 'true', color: '#19c1a5' }
    end
    rescue
      render nothing: true
  end


private

  def user_params
    params.require(:user).permit(:password, :password_confirmation, :url, 
      :location, :email, :first_name, :last_name, :username, :avatar, 
      :description)
  end

  def sort_order
    case params[:sort]
      when 'newest' then [:created_at, :desc]
      when 'most_likes' then [:like, :desc]
      when 'most_makes' then [:make, :desc]
      when 'recently_updated' then [:updated_at, :desc]
      else [:created_at, :desc]
    end     
  end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids = Photo.where(repository_id: repository_ids).group(:repository_id).minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h,e| h.merge!(e.repository_id => e) }
  end

end
