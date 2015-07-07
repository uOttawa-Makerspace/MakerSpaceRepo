class RepositoriesController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:index, :show]
  before_action :github_client, only: [:create, :show]
  before_action :set_repository, only: [:show, :add_like]

  # def index
  #   @repositories = Repository.order('created_at DESC').first(5)
  # end
  
  def show
    @photos = @repository.photos.first(5)
    @tags = @repository.tags
    @comments = @repository.comments.order(comment_filter).page params[:page]
    @vote = @user.upvotes.where(comment_id: @comments.map(&:id)).pluck(:comment_id, :downvote)
  end

  def new
    @repository = Repository.new
  end
  
  def edit
  end

  def create
    @repository = @user.repositories.build(repository_params)
    @repository.user_username = @user.username
    @client = github_client

    if @repository.github.present?
      githubatize = @repository.github.gsub(/\s+/, '-') #github replaces spaces with dashes in repo names
      @repository.github = githubatize
      @repository.github_url = "https://github.com/#{@client.login}/#{githubatize}"

      @client.create @repository.github, {description: @repository.description}
      @client.create_contents("#{@client.login}/#{@repository.github}", 
                              "README.md",
                              "Commit README.md",
                              "##{@repository.github}")
      commit if params['files'].present?
    end

    if @repository.save
      create_photos
      create_tags
      render json: { redirect_uri: "#{repository_path(@user.username, @repository.title)}" }
    else
      render :new, alert: "Something went wrong"
    end
  end

  def update
    respond_to do |format|
      if @repository.update(repository_params)
        format.html { redirect_to @repository, notice: 'Repository was successfully updated.' }
        format.json { render :show, status: :ok, location: @repository }
      else
        format.html { render :edit }
        format.json { render json: @repository.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @repository.destroy
    respond_to do |format|
      format.html { redirect_to repositories_url, notice: 'Repository was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  def add_like # MAKE A LIKE CONTROLLER TO PUT THIS IN
    @repository.likes.create!(user_id: @user.id)
    render json: { like: @repository.like }
    rescue
      render json: { failed: true}
  end

  private

    def set_repository
      @repository = Repository.find_by(title: params[:title])
    end

    def repository_params
      params.require(:repository).permit(:title, :description, :category, :license, :user_id, :github)
    end

    def comment_filter
      case params['comment_filter']
        when 'newest' then 'created_at DESC'
        when 'top' then 'upvote DESC'
        else 'upvote DESC'
      end
    end

    def create_photos
      params['images'].each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
      end if params['images'].present?
    end

    def create_tags
      params['tags'].each do |t|
        Tag.create(name: t, repository_id: @repository.id)
      end if params['tags'].present?
    end

    def commit
      repo = "#{@client.login}/#{@repository.github}"
      ref = "heads/master"
      blob_hash_array = []

      sha_latest_commit = @client.ref(repo, ref).object.sha
      sha_base_tree = @client.commit(repo, sha_latest_commit).commit.tree.sha

      params['files'].each do |f|
        blob_sha = @client.create_blob(repo, Base64.encode64(f.tempfile.read), "base64")
        blob_hash_array.push({ path: f.original_filename, mode: "100644", type: "blob", sha: blob_sha })
      end

      sha_new_tree = @client.create_tree( repo, blob_hash_array, {base_tree: sha_base_tree } ).sha
      commit_message = "Committed via MakerSpaceRepo!"
      sha_new_commit = @client.create_commit(repo, commit_message, sha_new_tree, sha_latest_commit).sha
      updated_ref = @client.update_ref(repo, ref, sha_new_commit)
    end

end

