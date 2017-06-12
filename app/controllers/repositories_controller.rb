class RepositoriesController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:index, :show]
  before_action :set_repository, only: [:show, :add_like, :destroy, :edit, :update, :download_files]

  def show
    @photos = @repository.photos.first(5)
    @files = @repository.repo_files.order("LOWER(file_file_name)")
    @categories = @repository.categories
    @equipments = @repository.equipments
    @comments = @repository.comments.order(comment_filter).page params[:page]
    @vote = @user.upvotes.where(comment_id: @comments.map(&:id)).pluck(:comment_id, :downvote)
  end

  def download
    url = "http://s3-us-west-2.amazonaws.com/uottawa-makerspace#{params[:file]}"
    data = open(url)
    send_data data.read, :type => data.content_type, :filename => File.basename(url), :x_sendfile => true
  end

  def download_files
    @files = @repository.repo_files.order("LOWER(file_file_name)")
    tmp_filename = "tmp_zip_#{@repository.title}" << Time.now.strftime("%Y%m%d%H%M%S").to_s << ".zip"
    temp_file  = Tempfile.new("#{tmp_filename}-#{@repository.title}")
    Zip::OutputStream.open(temp_file.path) do |zos|
      @files.each do |file|
        zos.put_next_entry(file.file_file_name)
        attachment = Paperclip.io_adapters.for(file.file)
        zos.print IO.read(attachment.path)
      end
    end

    filename = "#{@repository.title}_files_MakerRepo.zip"
    send_file temp_file.path, :type => 'application/zip',
                              :disposition => 'attachment',
                              :filename => filename
    temp_file.close
    cookies[:downloadStarted] = { :value => 1, :expires => 60.seconds.from_now }
  end

  def new
    @repository = Repository.new
  end

  def edit
    if (@repository.user_username == @user.username) || (@user.role == "admin")
      @photos = @repository.photos.first(5)
      @files = @repository.repo_files.order("LOWER(file_file_name)")
      @categories = @repository.categories
      @equipments = @repository.equipments
    else
      flash[:alert] = "You are not allowed to perform this action!"
      redirect_to repository_path(@repository.user_username, @repository.slug)
    end
  end

  def create
    @repository = @user.repositories.build(repository_params)
    @repository.user_username = @user.username

    if @repository.save
      @user.increment!(:reputation, 25)
      create_photos
      create_files
      create_categories
      create_equipments
      render json: { redirect_uri: "#{repository_path(@user.username, @repository.slug)}" }
      Repository.reindex
    else
      render json: @repository.errors["title"].first, status: :unprocessable_entity
    end

  end

  def update
    @repository.categories.destroy_all
    @repository.equipments.destroy_all

    if @repository.update(repository_params)
      update_photos
      update_files
      create_categories
      create_equipments
      flash[:notice] = "Project updated successfully!"
      render json: { redirect_uri: "#{repository_path(@repository.user_username, @repository.slug)}" }
      Repository.reindex
    else
      render json: @repository.errors["title"].first, status: :unprocessable_entity
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
    render json: { like: @repository.like, rep: repo_user.reputation }
    rescue
      render json: { failed: true }
  end

  private

    def set_repository
      @repository = Repository.find_by(user_username: params[:user_username], slug: params[:slug])
    end

    def repository_params
      params.require(:repository).permit(:title, :description, :license, :user_id)
    end

    def comment_filter
      case params['comment_filter']
        when 'newest' then 'created_at DESC'
        when 'top' then 'upvote DESC'
        else 'upvote DESC'
      end
    end

    def create_photos
      params['images'].first(5).each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
      end if params['images'].present?
    end

    def create_files
      params['files'].each do |f|
        RepoFile.create(file: f, repository_id: @repository.id)
      end if params['files'].present?
    end

    def update_photos
      @repository.photos.each do |img|
        if params['deleteimages'].include?(img.image_file_name) #checks if the file should be deleted
          Photo.destroy_all(image_file_name: img.image_file_name, repository_id: @repository.id)
        end
      end if params['deleteimages'].present?
      params['images'].each do |img|
        filename = img.original_filename.gsub(" ", "_");
        if @repository.photos.where(image_file_name: filename).blank? #checks if file exists
          dimension = FastImage.size(img.tempfile)
          Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
        else #updates existant files
          Photo.destroy_all(image_file_name: filename, repository_id: @repository.id)
          dimension = FastImage.size(img.tempfile)
          Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
        end
      end if params['images'].present?
    end

    def update_files
      @repository.repo_files.each do |f|
        if params['deletefiles'].include?(f.file_file_name) #checks if the file should be deleted
          RepoFile.destroy_all(file_file_name: f.file_file_name, repository_id: @repository.id)
        end
      end if params['deletefiles'].present?
      params['files'].each do |f|
        filename = f.original_filename.gsub(" ", "_");
        if @repository.repo_files.where(file_file_name: filename).blank? #checks if file exists
          RepoFile.create(file: f, repository_id: @repository.id)
        else #updates existant files
          RepoFile.destroy_all(file_file_name: filename, repository_id: @repository.id)
          RepoFile.create(file: f, repository_id: @repository.id)
        end
      end if params['files'].present?
    end

    def create_categories
      params['categories'].first(5).each do |c|
        Category.create(name: c, repository_id: @repository.id)
      end if params['categories'].present?
    end

    def create_equipments
      params['equipments'].first(5).each do |e|
        Equipment.create(name: e, repository_id: @repository.id)
      end if params['equipments'].present?
    end
end
