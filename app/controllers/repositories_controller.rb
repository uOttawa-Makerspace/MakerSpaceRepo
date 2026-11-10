class RepositoriesController < SessionsController
  include BCrypt
  include ZipKit::RailsStreaming
  before_action :current_user
  before_action :signed_in,
                except: %i[show download_files password_entry pass_authenticate]
  before_action :set_repository,
                only: %i[
                  show
                  add_like
                  destroy
                  edit
                  update
                  download_files
                  check_auth
                  pass_authenticate
                  password_entry
                ]
  # Password guessing: per repository and per user (or IP for guests)
  rate_limit to: 10, within: 10.minutes, only: :pass_authenticate,
             by: -> { "#{@repository.id}:#{@user.id.presence || request.remote_ip}" },
             with: -> {
               redirect_to password_entry_repository_path(denial_username(@repository), @repository.id),
                           alert: "Too many attempts. Please try again later."
             }
  before_action :redirect_to_owner_url, only: %i[show download_files password_entry]
  before_action :check_auth, only: %i[show download_files]
  before_action :require_sign_in_to_download, only: :download_files
  # Zip builds are expensive: per user and per address, staff and admin exempt
  rate_limit to: 20, within: 1.hour, only: :download_files, name: "download-user", if: -> { throttled_downloader? },
             by: -> { current_user.id }, with: -> { download_throttled }
  rate_limit to: 20, within: 1.hour, only: :download_files, name: "download-ip", if: -> { throttled_downloader? },
             by: -> { request.remote_ip }, with: -> { download_throttled }
  before_action -> { ensure_repository_unlocked(@repository) }, only: :add_like
  before_action :set_member_repository,
                only: %i[link_to_pp add_member remove_member]
  before_action :check_editable, only: %i[edit update]
  before_action :check_ownership, only: %i[destroy add_member remove_member]
  # Same rule as the show page's link form: members, staff and admin
  before_action :check_link_permission, only: :link_to_pp

  def show
    if @repository.private? && !@check_passed
      redirect_to password_entry_repository_path(
                    denial_username(@repository),
                    @repository.id
                  ) and return
    end

    # Replace `.page params[:page]` with `pagy(...)`:
    @pagy, @comments = pagy(@repository.comments.includes(:user).order(comment_filter), limit: 5)

    @vote =
      @user
        .upvotes
        .where(comment_id: @comments.map(&:id))
        .pluck(:comment_id, :downvote)
    @project_proposals =
      ProjectProposal.approved.by_semester.map do |p|
        [
          p.title,
          p.id,
          { data: { semester: p.active_semester_label } }
        ]
      end

    @liked = @repository.likes.find_by(user_id: @user.id).nil? ? false : true

    remember_recently_viewed
  end

  # Adds this repository to the recently viewed cookie (the last five). A cookie that is missing or
  # not a JSON object starts the list again.
  def remember_recently_viewed
    link = repository_path(id: @repository.id, user_username: @repository.user_username)
    recently_viewed = parse_recently_viewed
    unless recently_viewed.key?(link)
      recently_viewed[link] = @repository.title[..35]
      recently_viewed = recently_viewed.take(5).to_h
    end
    cookies[:recently_viewed] = JSON.generate(recently_viewed)
  end
  private :remember_recently_viewed

  def parse_recently_viewed
    parsed = JSON.parse(cookies[:recently_viewed].to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
  private :parse_recently_viewed

  def download_files
    # Verify authorization for private repositories
    if @repository.private? && !@check_passed
      redirect_to password_entry_repository_path(denial_username(@repository), @repository.id), alert: "Password required" and return
    end

    if @repository.repo_files.empty?
      flash[:alert] = "This repository has no files to download."
      redirect_to repository_path(@repository.user_username, @repository.slug) and return
    end

    zip = Repository::ZipCache.new(@repository).fetch
    # If no files actually existed in S3, there is no zip to send
    if zip.empty?
      flash[:alert] = "None of the files for this repository could be found in storage."
      redirect_to repository_path(@repository.user_username, @repository.slug) and return
    end

    send_zip(zip)
  end

  def new
    @repository = Repository.new
    @project_proposals =
      ProjectProposal.approved.order(title: :asc).pluck(:title, :id) if params[
      :project_proposal_id
    ].blank?
  end

  def edit
    if @repository.editable_by?(@user) || @user.admin?
      @project_proposals =
        ProjectProposal.approved.order(title: :asc).pluck(:title, :id) if params[
        :project_proposal_id
      ].blank?
    else
      flash[:alert] = 'You are not allowed to perform this action!'
      redirect_to repository_path(denial_username(@repository), @repository.slug)
    end
  end


  # The repository, its owners, categories and equipment are stored together or not at all; the
  # reputation is awarded once that has committed.
  def create
    @repository = Repository.new(user_id: @user.id, users: [@user, *extra_owners])

    if save_with_categories_and_equipments
      @user.increment!(:reputation, 25)
      redirect_to repository_path(@user.username, @repository.slug).to_s
    else
      @project_proposals =
        ProjectProposal.approved.order(title: :asc).pluck(:title, :id)
      render "new", status: :unprocessable_content
    end
  end

  def update
    if save_with_categories_and_equipments
      flash[:notice] = "Project updated successfully!"
      redirect_to repository_path(
                    @repository.user_username,
                    @repository.slug
                  ).to_s
    else
      @project_proposals =
        ProjectProposal.approved.order(title: :asc).pluck(:title, :id) if params[
        :project_proposal_id
      ].blank?
      flash.now[:alert] = validation_message(@repository, "errors.repositories.not_updated")
      render 'edit', status: :unprocessable_content
    end
  end

  def destroy
    @repository.destroy
    respond_to do |format|
      format.html do
        redirect_to user_path(@repository.user_username),
                    notice: "Repository has been successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def add_like
    current_like = @repository.likes.find_by(user_id: @user.id)

    # Members do not like their own repository (a like already given can still be taken back).
    if current_like.nil? && @repository.editable_by?(@user)
      flash[:alert] = "You cannot like a project you are a member of"
      return redirect_to repository_path(@repository.user_username, @repository.slug)
    end

    if current_like.nil?
      # A repeated click or a simultaneous request finds the like already given and counts nothing again.
      @repository.users.each { |u| u.increment!(:reputation, 5) } if Like.give(@repository, @user)
      flash[:notice] = "You have liked this project!"
    else
      take_back_like
      flash[:notice] = "You have unliked this project"
    end
    redirect_to repository_path(@repository.user_username, @repository.slug)
  end

  def password_entry
    if !@repository.private?
      redirect_to repository_path(@repository.user_username, @repository.id)
    end
  end

  def pass_authenticate
    unless @repository.private?
      redirect_to repository_path(@repository.user_username, @repository.slug) and return
    end

    @auth =
      @repository.password.present? && @repository.pword == params[:password]
    respond_to do |format|
      if @auth
        @authorized = true
        authorized_repo_ids << @repository.id
        flash[:notice] = "Success"
        format.html do
          redirect_to repository_path(
                        @repository.user_username,
                        @repository.slug
                      )
        end
      else
        @authorized = false
        flash[:alert] = "Incorrect password. Try again!"
        format.html do
          redirect_to password_entry_repository_path(
                        denial_username(@repository),
                        @repository.id
                      )
        end
      end
    end
  end

  def link_to_pp
    repository = @repository
    project_proposal_id = params[:repo][:project_proposal_id]
    if project_proposal_id.present? &&
       !ProjectProposal.approved.exists?(id: project_proposal_id)
      flash[:alert] = "Only an approved Project Proposal can be linked."
      redirect_to repository_path(repository.user_username, repository.slug) and return
    end
    repository.project_proposal_id = project_proposal_id
    write_flash(repository, "errors.repositories.proposal_not_linked",
                "This Repository was linked to the selected Project Proposal") { repository.save }
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def add_member
    repository = @repository
    member_username = params[:repo_owner][:owner_username]
    member = User.find_by_username(member_username)

    if member.nil?
      flash[:alert] = "Couldn't find user, please try again."
      redirect_to repository_path(repository.user_username, repository.slug)
      return
    elsif repository.users.include? member
      flash[:alert] = "This user is already a member of your repository."
      redirect_to repository_path(repository.user_username, repository.slug)
      return
    end

    repository.users << member

    write_flash(repository, "errors.repositories.member_not_added", "This user was added to your repository.") { repository.save }
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def remove_member
    repository = @repository
    member_id = params[:repo_owner][:owner_id]
    member = User.find_by(id: member_id)

    if member.nil?
      flash[:alert] = "Couldn't find user, please try again."
    elsif !repository.users.include?(member)
      flash[:alert] = "This user is not a member of this repository."
    elsif repository.users.length == 1
      flash[
        :alert
      ] = "You cannot remove the last person in this repository. Please go to your profile page if you want to delete this repository."
    elsif member.id == repository.user_id
      flash[:alert] = "You cannot remove the current owner of this repository."
    else
      repository.users.delete(member)
      flash[:notice] = "This user was removed from your repository."
    end
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def transfer_owner
    repository = Repository.find(params[:repo_owner][:repository_id])
    member_id = params[:repo_owner][:owner_id]
    member = User.find_by(id: member_id)

    if member.nil?
      flash[:alert] = "Couldn't find user, please try again."
    elsif current_user.username != repository.user_username &&
          !current_user.admin?
      flash[
        :alert
      ] = "You don't have the right permissions to perform this action"
    elsif !repository.users.include? member
      flash[:alert] = "This user is not a member of your repository."
    elsif member.id == repository.user_id
      flash[:alert] = "This user is already the owner of the repository."
    else
      write_flash(repository, "errors.repositories.ownership_not_transferred",
                  "Repository ownership was successfully transferred.") { repository.update(user_id: member_id) }
    end
    redirect_to repository_path(denial_username(repository), repository.slug)
  end

  def populate_users
    # Only the fields the user-search autocompletes read (repositories.js, teams.js, add_new_staff.js)
    json_data =
      User
        .where(
          "LOWER(name) like LOWER(?)",
          "%#{User.sanitize_sql_like(params[:search].to_s)}%"
        )
        .limit(10)
        .pluck(:id, :name, :username)
        .map { |id, name, username| { id: id, name: name, username: username } }
    render json: { users: json_data }
  end

  private

  # Only the request that actually removed the like takes the reputation back.
  def take_back_like
    return unless Like.take_back(@repository, @user)

    @repository.users.each { |u| u.decrement!(:reputation, 5) }
  end

  # Edit and update: the owner, a member or an admin.
  def check_editable
    refuse_action unless @user.admin? || @repository.editable_by?(@user)
  end

  # Delete and member management: the owner or an admin.
  def check_ownership
    refuse_action unless @user.admin? || @repository.owned_by?(@user)
  end

  def refuse_action
    flash[:alert] = "You are not allowed to perform this action!"
    redirect_to repository_path(denial_username(@repository), @repository.slug)
  end

  def set_member_repository
    key = params.key?(:repo) ? :repo : :repo_owner
    @repository = Repository.find(params.expect(key => [:repository_id])[:repository_id])
  end

  def check_link_permission
    unless @user.staff? || @user.admin? || @repository.editable_by?(@user)
      flash[:alert] = "You are not allowed to perform this action!"
      redirect_to repository_path(denial_username(@repository), @repository.slug)
    end
  end

  def require_sign_in_to_download
    return if signed_in?

    redirect_to login_path(back_to: login_back_to), alert: "Sign in to download this repository."
  end

  def throttled_downloader?
    !current_user.staff?
  end

  def download_throttled
    render plain: "Too many downloads, please try again later.", status: :too_many_requests
  end

  def zip_download_name
    "#{@repository.title.parameterize.presence || 'repository'}-#{@repository.id}.zip"
  end

  # A cached zip is sent from disk; otherwise it streams from storage as it is built.
  def send_zip(zip)
    return send_file(zip.path, type: "application/zip", filename: zip_download_name) if zip.path

    zip_kit_stream(filename: zip_download_name) { |streamer| Repository::ZipCache.write_entries(streamer, zip.entries) }
  end

  def check_auth
    @check_passed = repository_unlocked?(@repository)
  end

  # The username in the address is the owner's: a link with another (or an old) username is sent on to the
  # repository's own address, for people who may see the repository. A locked private repository is not sent on, so
  # the redirect cannot name its owner.
  def redirect_to_owner_url
    username = @repository.user_username
    return if username.blank? || params[:user_username] == username
    return if @repository.private? && !repository_unlocked?(@repository)

    redirect_to url_for(action: action_name, user_username: username, id: params[:id], only_path: true, **request.query_parameters.symbolize_keys),
                status: :found
  end

  def set_repository
    id = params[:id].split(".", 2)[0]
    @repository = Repository
                    .where(id: id)
                    .or(Repository.where(slug: id))
                    .or(Repository.where(title: id))
                    .first!
  end

  def repository_params
    params.require(:repository).permit(
      :title,
      :description,
      :license,
      :share_type,
      :password,
      :youtube_link,
      :project_proposal_id,
      categories: [],
      equipments: [],
      photos_attributes: [:id, :image, :_destroy, :position],
      repo_files_attributes: [:id, :file, :_destroy]
    )
  end

  def comment_filter
    case params["comment_filter"]
    when "newest"
      "created_at DESC"
    when "top"
      "upvote DESC"
    else
      "upvote DESC"
    end
  end

  # Like categories: names not sent (nil) keep the stored equipment; a list, even an empty one, replaces it with up
  # to five non-blank names.
  def replace_equipments(names)
    return if names.nil?

    @repository.equipments.destroy_all
    names.compact_blank.first(5).each do |e|
      # Create EquipmentOption if not there already.
      EquipmentOption.find_or_create_by(name: e)
      Equipment.create(name: e, repository_id: @repository.id)
    end
  end

  # The new or edited repository is validated and saved first; categories and equipment are replaced only once it
  # has saved, in the same transaction, so a refused or failed save stores nothing and leaves them as they were.
  def save_with_categories_and_equipments
    Repository.transaction do
      attributes = repository_params.except(:categories, :equipments).merge(password_attributes)
      next false unless @repository.update_with_categories(attributes, repository_params[:categories])

      @repository.store_id_slug!
      replace_equipments(repository_params[:equipments])
      true
    end
  end

  # A public share type clears the password; a private one changes it only when a new one is sent.
  def password_attributes
    if repository_params[:share_type].eql?("public")
      { password: nil }
    elsif params[:password].present?
      { password: BCrypt::Password.create(params[:password].join("")) }
    else
      {}
    end
  end

  # Other members named on the new repository form; unknown ids are skipped.
  def extra_owners
    User.where(id: Array(params[:owner])).where.not(id: @user.id)
  end
end
