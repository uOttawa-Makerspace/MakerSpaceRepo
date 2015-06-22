class UsersController < SessionsController

  skip_before_action :session_expiry, only: [:create]
  before_action :current_user, except: [:create, :new]
  before_action :signed_in, except: [:new, :create, :show]
    
  def create
    @user = User.new(user_params)
    @user.pword = params[:user][:password] if @user.valid?
    
    respond_to do |format|
      if @user.save
        session[:user_id], cookies[:user_id] = @user.id, @user.id
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
      redirect_to edit_user_path(@user), notice: 'Profile updated!'
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
  end

  def destroy
    @user.destroy
    disconnect_user
    redirect_to root_path
  end

  def vote
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

end
