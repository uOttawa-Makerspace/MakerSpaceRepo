class RepositoriesController < SessionsController
  include BCrypt
  before_action :current_user, :check_session
  before_action :signed_in, except: %i[show download_files]
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
  before_action :check_auth, only: [:show]
  before_action :check_ownership, only: %i[edit update destroy]

  def show
    if @repository.private? && !@check_passed
      redirect_to password_entry_repository_path(
                    @repository.user_username,
                    @repository.id
                  ) and return
    end

    @photos = @repository.photos.joins(:image_attachment)&.first(5) || []
    @files = @repository.repo_files.joins(:file_attachment)
    @categories = @repository.categories
    @equipments = @repository.equipments
    @comments = @repository.comments.order(comment_filter).page params[:page]
    @vote =
      @user
        .upvotes
        .where(comment_id: @comments.map(&:id))
        .pluck(:comment_id, :downvote)
    @project_proposals =
      ProjectProposal.approved.order(title: :asc).pluck(:title, :id)
    @members = @repository.users
    @all_users = User.where.not(id: @members.pluck(:id)).pluck(:name, :id)
    @liked = @repository.likes.find_by(user_id: @user.id).nil? ? false : true

    # Add this repo to recently viewed cookie
    # Don't trust user cookies, they might crash the parser
    begin
      this_link =
        repository_path id: @repository.id,
                        user_username: @repository.user_username
      this_proj_name = @repository.title[..35]
      # make sure we parse an array, not something else
      # hash of link => project name
      recently_viewed =
        begin
          JSON.parse(cookies[:recently_viewed])
        rescue StandardError
          {}
        end
      recently_viewed = {} unless recently_viewed.kind_of? Hash
      # if this is a new link
      unless recently_viewed.has_key? this_link
        recently_viewed[this_link] = this_proj_name
        recently_viewed = recently_viewed.take(5).to_h
      end
    rescue StandardError
      # nuke cookies
      cookies[:recently_viewed] = nil
    else # success running
      cookies[:recently_viewed] = JSON.generate(recently_viewed)
    end
  end

  def download_files
    @files = @repository.repo_files

    file_location =
      "#{Rails.root}/public/tmp/makerepo_file_#{@repository.id.to_s}.zip"
    directory = File.dirname(file_location)

    FileUtils.mkdir_p(directory) unless File.directory?(directory)
    File.delete(file_location) if File.file?(file_location)

    Zip::File.open(file_location, create: true) do |zip|
      @files.each do |file|
        downloaded_file_path = "#{Rails.root}/public/tmp/#{file.file.filename}"
        if file.file.attached? &&
             file.file.blob.service.exist?(file.file.blob.key)
          File.open(downloaded_file_path, "wb") do |downloaded_file|
            downloaded_file.write(file.file.download)
          end
          if zip.find_entry(file.file.filename)
            filename =
              file.file.filename.to_s.split(".")[0] + "_1." +
                file.file.filename.to_s.split(".")[1]
          else
            filename = file.file.filename
          end
          zip.add(filename, downloaded_file_path)
        end
      end
    end

    @files.each do |file|
      downloaded_file_path = "#{Rails.root}/public/tmp/#{file.file.filename}"
      File.delete(downloaded_file_path) if File.exist?(downloaded_file_path)
    end

    if File.exist?(file_location)
      File.open(file_location, "r") do |f|
        send_data f.read,
                  type: "application/zip",
                  filename: "makerepo_file_#{@repository.id.to_s}.zip"
      end
      File.delete(file_location)
    else
      flash[:error] = "Unable to download file: File not found."
      redirect_to root_path
    end
  end

  def new
    @repository = Repository.new
    @project_proposals =
      ProjectProposal.approved.order(title: :asc).pluck(:title, :id) if params[
      :project_proposal_id
    ].blank?
  end

  def edit
    if @repository.users.pluck(:email).include?(@user.email) || (@user.role == "admin")
      @files = @repository.repo_files.joins(:file_attachment)
      @categories = @repository.categories
      @equipments = @repository.equipments
      @project_proposals =
      ProjectProposal.approved.order(title: :asc).pluck(:title, :id) if params[
      :project_proposal_id
    ].blank?
    else
      flash[:alert] = "You are not allowed to perform this action!"
      redirect_to repository_path(@repository.user_username, @repository.slug)
    end
  end

  def create
    @repository =
      Repository.new(repository_params.except(:categories, :equipments))
    @repository.user_id = @user.id
    @repository.users << @user
    @repository.user_username = @user.username
    update_password

    if @repository.save
      @user.increment!(:reputation, 25)

      if params[:owner].present?
        params[:owner].each do |owner|
          if User.exists?(id: owner)
            @repository.users << User.find_by(id: owner)
          end
        end
        @repository.save
      end
      
      create_categories
      create_equipments
      redirect_to repository_path(@user.username, @repository.slug).to_s
    else
      @project_proposals =
        ProjectProposal.approved.order(title: :asc).pluck(:title, :id)
      render "new", status: :unprocessable_entity
    end
  end

  def update
    @repository.categories.destroy_all
    @repository.equipments.destroy_all
    update_password
    if @repository.update(repository_params.except(:categories, :equipments))
      create_categories
      create_equipments
      flash[:notice] = "Project updated successfully!"
      redirect_to repository_path(
                    @repository.user_username,
                    @repository.slug
                  ).to_s
    else
      flash[:alert] = "Unable to apply the changes."
      render json: @repository.errors.to_hash(true),
             status: :unprocessable_entity
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

    if current_like.nil?
      @repository.likes.create!(user_id: @user.id)
      @repository.users.each { |u| u.increment!(:reputation, 5) }
      flash[:notice] = "You have liked this project!"
    else
      current_like.destroy
      @repository.users.each { |u| u.decrement!(:reputation, 5) }
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
    @auth = Repository.authenticate(params[:id], params[:password])
    respond_to do |format|
      if @auth
        @authorized = true
        authorized_repo_ids << params[:id]
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
                        @repository.user_username,
                        @repository.id
                      )
        end
      end
    end
  end

  def link_to_pp
    repository = Repository.find params[:repo][:repository_id]
    project_proposal_id = params[:repo][:project_proposal_id]
    repository.project_proposal_id = project_proposal_id
    if repository.save
      flash[
        :notice
      ] = "This Repository was linked to the selected Project Proposal"
    else
      flash[:alert] = "Something went wrong."
    end
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def add_member
    repository = Repository.find params[:repo_owner][:repository_id]
    member_username = params[:repo_owner][:owner_username]
    member = User.find_by(username: member_username)

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

    if repository.save
      flash[:notice] = "This user was added to your repository."
    else
      flash[:alert] = "Something went wrong."
    end
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def remove_member
    repository = Repository.find params[:repo_owner][:repository_id]
    member_id = params[:repo_owner][:owner_id]
    member = User.find_by(id: member_id)

    if member.nil?
      flash[:alert] = "Couldn't find user, please try again."
    elsif repository.users.length == 1
      flash[
        :alert
      ] = "You cannot remove the last person in this repository. Please go to your profile page if you want to delete this repository."
    elsif member.id == repository.user_id
      flash[:alert] = "You cannot remove the current owner of this repository."
    elsif repository.users.delete(member)
      flash[:notice] = "This user was removed from your repository."
    else
      flash[:alert] = "Something went wrong."
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
    elsif repository.update(user_id: member_id, user_username: member.username)
      flash[:notice] = "Repository ownership was successfully transferred."
    else
      flash[
        :alert
      ] = "Something went wrong when transferring ownership. Please try again later."
    end
    redirect_to repository_path(repository.user_username, repository.slug)
  end

  def populate_users
    json_data =
      User.where("LOWER(name) like LOWER(?)", "%#{params[:search]}%").map(
        &:as_json
      )
    render json: { users: json_data }
  end

  private

  # Block if user is not authorized to modify repository
  def check_ownership
    # admins can modify repo
    unless @user.admin? || @repository.users.include?(@user)
      flash[:alert] = "You are not allowed to perform this action!"
      redirect_to repository_path(@repository.user_username, @repository.slug)
    end
  end

  def check_session
    @authorized = true if authorized_repo_ids.include? params[:id]
  end

  def check_auth
    @check_passed =
      if @authorized || @user.admin? || @user.staff? ||
           (@repository.user_username == @user.username)
        true
      else
        false
      end
  end

  def set_repository
    id = params[:id].split(".", 2)[0]
    @repository =
      if Repository.where(id: id).present?
        Repository.find(id)
      elsif Repository.find_by(slug: id)
        Repository.find_by(slug: id)
      else
        Repository.find_by(title: id)
      end
    redirect_to root_path, alert: "Repository not found" unless @repository
  end

  def repository_params
    params.require(:repository).permit(
      :title,
      :description,
      :license,
      :user_id,
      :share_type,
      :password,
      :youtube_link,
      :project_proposal_id,
      categories: [],
      equipments: [],
      photos_attributes: [:id, :image, :_destroy],
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

  def create_categories
    if params[:repository][:categories].present?
      params[:repository][:categories]
        .first(5)
        .each { |c| Category.create(name: c, repository_id: @repository.id) }
    end
  end

  def create_equipments
    if params[:repository][:equipments].present?
      params[:repository][:equipments]
        .first(5)
        .each { |e| Equipment.create(name: e, repository_id: @repository.id) }
    end
  end

  def update_password
    if repository_params[:share_type].eql?("public")
      @repository.password = nil
      @repository.save
    else
      if params[:password].present?
        pass = params[:password].join("")
        @repository.update(password: BCrypt::Password.create(pass))
      end
    end
  end
end
