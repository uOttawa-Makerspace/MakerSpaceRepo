class RepositoriesController < SessionsController
  include BCrypt
  before_action :current_user, :check_session
  before_action :signed_in, except: %i[index show download download_files]
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
                ]
  before_action :check_auth, only: [:show]

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
  end

  def download_files
    @files = @repository.repo_files

    file_location =
      "#{Rails.root}/public/tmp/makerepo_file_#{@repository.id.to_s}.zip"
    directory = File.dirname(file_location)

    FileUtils.mkdir_p(directory) unless File.directory?(directory)
    File.delete(file_location) if File.file?(file_location)

    Zip::ZipFile.open(file_location, Zip::File::CREATE) do |zip|
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
    if @repository.users.pluck(:email).include?(@user.email) ||
         (@user.role == "admin")
      @photos = @repository.photos.joins(:image_attachment).first(5)
      @files = @repository.repo_files.joins(:file_attachment)
      @categories = @repository.categories
      @equipments = @repository.equipments
    else
      flash[:alert] = "You are not allowed to perform this action!"
      redirect_to repository_path(@repository.user_username, @repository.slug)
    end
  end

  def create
    # @repository = @user.repositories.build(repository_params)
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
      begin
        create_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        Airbrake.notify(e)
        flash[
          :alert
        ] = "Something went wrong while uploading photos, please try again later."
        @repository.destroy
        redirect_to request.path
      else
        create_files
        create_categories
        create_equipments
        redirect_to repository_path(@user.username, @repository.slug).to_s
      end
    else
      @project_proposals =
        ProjectProposal.approved.order(title: :asc).pluck(:title, :id)
      render "new", status: 422
    end
  end

  def update
    @repository.categories.destroy_all
    @repository.equipments.destroy_all
    update_password
    if @repository.update(repository_params.except(:categories, :equipments))
      update_files
      create_categories
      create_equipments
      begin
        update_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        Airbrake.notify(e)
        flash[
          :alert_yellow
        ] = "Something went wrong while uploading photos, try uploading them again later. Other changes have been saved."
        redirect_to repository_path(
                      @repository.user_username,
                      @repository.slug
                    ).to_s
      else
        flash[:notice] = "Project updated successfully!"
        redirect_to repository_path(
                      @repository.user_username,
                      @repository.slug
                    ).to_s
      end
    else
      flash[:alert] = "Unable to apply the changes."
      render json: @repository.errors["title"].first,
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

  def add_like # MAKE A LIKE CONTROLLER TO PUT THIS IN
    @repository.likes.create!(user_id: @user.id)
    @repository.users.each { |u| u.increment!(:reputation, 5) }
    flash[:notice] = "You have liked this project!"
    redirect_to repository_path(@repository.user_username, @repository.slug)
  rescue StandardError
    render json: { failed: true }
  end

  def password_entry
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
                        @repository.slug
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
    member_id = params[:repo_owner][:owner_id]
    member = User.find_by(id: member_id)

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
      equipments: []
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

  def create_photos
    if params[:images].present?
      params[:images]
        .first(5)
        .each do |img|
          dimension = FastImage.size(img.tempfile, raise_on_failure: true)
          Photo.create(
            image: img,
            repository_id: @repository.id,
            width: dimension.first,
            height: dimension.last
          )
        end
    end
  end

  def create_files
    if params[:files].present?
      params[:files].each do |f|
        RepoFile.create(file: f, repository_id: @repository.id)
      end
    end
  end

  def update_photos
    if params[:deleteimages].present?
      @repository.photos.each do |img|
        if params[:deleteimages].include?(img.image.filename.to_s)
          # checks if the file should be deleted
          img.image.purge
          img.destroy
        end
      end
    end

    if params["images"].present?
      params["images"].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          repository_id: @repository.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def update_files
    if params["deletefiles"].present?
      @repository.repo_files.each do |f|
        if params["deletefiles"].include?(f.file.id.to_s)
          # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params["files"].present?
      params["files"].each do |f|
        RepoFile.create(file: f, repository_id: @repository.id)
      end
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
