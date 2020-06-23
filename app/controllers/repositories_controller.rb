class RepositoriesController < SessionsController
  before_action :current_user, :check_session
  before_action :signed_in, except: %i[index show download download_files]
  before_action :set_repository, only: %i[show add_like destroy edit update download_files check_auth pass_authenticate]
  before_action :check_auth, only: [:show]

  def show
    if @repository.private? && !@check_passed
      redirect_to password_entry_repository_path(@repository.user_username, @repository.slug) and return
    end

    @photos = @repository.photos&.first(5) || []
    @files = @repository.repo_files
    @categories = @repository.categories
    @equipments = @repository.equipments
    @comments = @repository.comments.order(comment_filter).page params[:page]
    @vote = @user.upvotes.where(comment_id: @comments.map(&:id)).pluck(:comment_id, :downvote)
    @project_proposals = ProjectProposal.all.where(approved: 1).pluck(:title, :id)
    @owners = @repository.users
    @all_users = User.where.not(id: @owners.pluck(:id)).pluck(:name, :id)
  end

  def download
    url = "http://s3-us-west-2.amazonaws.com/uottawa-makerspace#{params[:file]}"
    data = open(url)
    send_data data.read, type: data.content_type, filename: File.basename(url), x_sendfile: true
  end

  def download_files
    @files = @repository.repo_files.order('LOWER(file_file_name)')
    tmp_filename = "tmp_zip_#{@repository.title}" << Time.zone.now.strftime('%Y%m%d%H%M%S').to_s << '.zip'
    temp_file = Tempfile.new("#{tmp_filename}-#{@repository.title}")
    Zip::OutputStream.open(temp_file.path) do |zos|
      @files.each do |file|
        zos.put_next_entry(file.file_file_name)
        attachment = Paperclip.io_adapters.for(file.file)
        zos.print IO.read(attachment.path)
      end
    end

    filename = "#{@repository.title}_files_MakerRepo.zip"
    send_file temp_file.path, type: 'application/zip',
              disposition: 'attachment',
              filename: filename
    temp_file.close
    cookies[:downloadStarted] = {value: 1, expires: 60.seconds.from_now}
  end

  def new
    @repository = Repository.new
  end

  def edit
    if @repository.users.pluck(:email).include?(@user.email) || (@user.role == 'admin')
      @photos = @repository.photos.first(5)
      @files = @repository.repo_files
      @categories = @repository.categories
      @equipments = @repository.equipments
    else
      flash[:alert] = 'You are not allowed to perform this action!'
      redirect_to repository_path(@repository.user_username, @repository.slug)
    end
  end

  def create
    # @repository = @user.repositories.build(repository_params)
    @repository = Repository.new(repository_params)
    @repository.user_id = @user.id
    @repository.users << @user
    @repository.user_username = @user.username

    if @repository.save
      @user.increment!(:reputation, 25)
      create_photos
      create_files
      create_categories
      create_equipments
      render json: {redirect_uri: repository_path(@user.username, @repository.slug).to_s}
    else
      render json: @repository.errors['title'].first, status: :unprocessable_entity
    end
  end

  def update
    @repository.categories.destroy_all
    @repository.equipments.destroy_all
    update_password
    if @repository.update(repository_params)
      update_photos
      update_files
      create_categories
      create_equipments
      flash[:notice] = 'Project updated successfully!'
      render json: {redirect_uri: repository_path(@repository.user_username, @repository.slug).to_s}
    else
      flash[:alert] = 'Unable to apply the changes.'
      render json: @repository.errors['title'].first, status: :unprocessable_entity
    end
  end

  def destroy
    @repository.destroy
    respond_to do |format|
      format.html { redirect_to user_path(@repository.user_username), notice: 'Repository has been successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def add_like # MAKE A LIKE CONTROLLER TO PUT THIS IN
    @repository.likes.create!(user_id: @user.id)
    repo_user = @repository.user
    repo_user.increment!(:reputation, 5)
    render json: {like: @repository.like, rep: repo_user.reputation}
  rescue StandardError
    render json: {failed: true}
  end

  def password_entry;
  end

  def pass_authenticate
    @auth = Repository.authenticate(params[:slug], params[:password])
    respond_to do |format|
      if @auth
        @authorized = true
        authorized_repo_ids << params[:id]
        flash[:notice] = 'Success'
        format.html { redirect_to repository_path(@repository.user_username, @repository.slug) }
      else
        @authorized = false
        flash[:alert] = 'Incorrect password. Try again!'
        format.html { redirect_to password_entry_repository_path(@repository.user_username, @repository.slug) }
      end
    end
  end

  def link_to_pp
    repository = Repository.find params[:repo][:repository_id]
    project_proposal_id = params[:repo][:project_proposal_id]
    repository.project_proposal_id = project_proposal_id
    if repository.save
      flash[:notice] = 'This Repository was linked to the selected Project Proposal'
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = 'Something went wrong.'
      redirect_back(fallback_location: root_path)
    end
  end

  def add_owner
    repository = Repository.find params[:repo_owner][:repository_id]
    owner_id = params[:repo_owner][:owner_id]
    repository.users << User.find(owner_id)
    if repository.save
      flash[:notice] = 'This owner was added to your repository'
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = 'Something went wrong.'
      redirect_back(fallback_location: root_path)
    end
  end

  def remove_owner
    repository = Repository.find params[:repo_owner][:repository_id]
    owner_id = params[:repo_owner][:owner_id]
    owner = User.find(owner_id)
    if repository.users.delete(owner)
      flash[:notice] = 'This owner was removed from your repository'
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = 'Something went wrong.'
      redirect_back(fallback_location: root_path)
    end
  end

  private

  def check_session
    @authorized = true if authorized_repo_ids.include? params[:id]
  end

  def check_auth
    @check_passed = if @authorized == true || @user.admin? || @user.staff? || (@repository.user_username == @user.username)
                      true
                    else
                      false
                    end
  end

  def set_repository
    @repository = Repository.find_by(slug: params[:slug])
  end

  def repository_params
    params.require(:repository).permit(:title, :description, :license, :user_id, :share_type, :password, :youtube_link, :project_proposal_id)
  end

  def comment_filter
    case params['comment_filter']
    when 'newest' then
      'created_at DESC'
    when 'top' then
      'upvote DESC'
    else
      'upvote DESC'
    end
  end

  def create_photos
    if params['images'].present?
      params['images'].first(5).each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
      end
    end
  end

  def create_files
    if params['files'].present?
      params['files'].each do |f|
        RepoFile.create(file: f, repository_id: @repository.id)
      end
    end
  end

  def update_photos
    if params['deleteimages'].present?
      @repository.photos.each do |img|
        if params['deleteimages'].include?(img.image.filename.to_s) # checks if the file should be deleted
          img.image.purge
          img.destroy
        end
      end
    end

    if params['images'].present?
      params['images'].each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
      end
    end
  end

  def update_files
    if params['deletefiles'].present?
      @repository.repo_files.each do |f|
        if params['deletefiles'].include?(f.file.filename.to_s) # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params['files'].present?

      params['files'].each do |f|
        RepoFile.create(file: f, repository_id: @repository.id)
      end

    end
  end

  def create_categories
    if params['categories'].present?
      params['categories'].first(5).each do |c|
        Category.create(name: c, repository_id: @repository.id)
      end
    end
  end

  def create_equipments
    if params['equipments'].present?
      params['equipments'].first(5).each do |e|
        Equipment.create(name: e, repository_id: @repository.id)
      end
    end
  end

  def update_password
    if repository_params['share_type'].eql?('public')
      @repository.password = nil
      @repository.save
    else
      if params['password'].present?
        @repository.pword = params['password']
        @repository.save
      end
    end
  end
end
