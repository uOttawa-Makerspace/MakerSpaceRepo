class RepositoriesController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:index, :show]
  before_action :github_client, only: [:create, :show, :edit]
  before_action :set_repository, only: [:show, :add_like, :destroy, :edit, :update]

  def show
    @photos = @repository.photos.first(5)
    @categories = @repository.categories
    @equipments = @repository.equipments
    @comments = @repository.comments.order(comment_filter).page params[:page]
    @vote = @user.upvotes.where(comment_id: @comments.map(&:id)).pluck(:comment_id, :downvote)
  end

  def new
    @repository = Repository.new
  end
  
  def edit
    @photos = @repository.photos.first(5)
    @categories = @repository.categories
    @equipments = @repository.equipments
  end

  def create
    @repository = @user.repositories.build(repository_params)
    @repository.user_username = @user.username
    github
    commit if params['files'].present?

    if @repository.save
      @user.increment!(:reputation, 25)
      create_photos
      create_categories
      create_equipments
      render json: { redirect_uri: "#{repository_path(@user.username, @repository.slug)}" }
      Repository.reindex
    else
      render json: @repository.errors["title"].first, status: :unprocessable_entity
    end

  end

  def update
    github if @repository.github_changed?
    commit if params['files'].present?
    @repository.remove_duplicate_photos(params['images'])
    @repository.categories.destroy_all
    @repository.equipments.destroy_all

    if @repository.update(repository_params)
      create_photos
      create_categories
      create_equipments
      render json: { redirect_uri: "#{repository_path(@user.username, @repository.slug)}" }
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
      params.require(:repository).permit(:title, :description, :license, :user_id, :github)
    end

    def comment_filter
      case params['comment_filter']
        when 'newest' then 'created_at DESC'
        when 'top' then 'upvote DESC'
        else 'upvote DESC'
      end
    end

    def github
      if @repository.github.present?
        githubatize = @repository.github.strip.gsub(/\s+/, '-') #github replaces spaces with dashes in repo names
        @repository.github = githubatize
        @repository.github_url = "https://github.com/#{@github_client.login}/#{githubatize}"
        @repos = @github_client.repos.inject([]) { |a,e| a.push(e.name) }

        unless @repos.include? @repository.github
          @github_client.create @repository.github, {description: @repository.description}
          @github_client.create_contents("#{@github_client.login}/#{@repository.github}", 
                                  "README.md",
                                  "Commit README.md",
                                  "##{@repository.github}")
        end
      end    
    end

    def create_photos
      params['images'].first(5).each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repository.id, width: dimension.first, height: dimension.last)
      end if params['images'].present?
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

    def commit
      repo = "#{@github_client.login}/#{@repository.github}"
      ref = "heads/master"
      blob_hash_array = []

      sha_latest_commit = @github_client.ref(repo, ref).object.sha
      sha_base_tree = @github_client.commit(repo, sha_latest_commit).commit.tree.sha

      params['files'].each do |f|
        blob_sha = @github_client.create_blob(repo, Base64.encode64(f.tempfile.read), "base64")
        blob_hash_array.push({ path: f.original_filename, mode: "100644", type: "blob", sha: blob_sha })
      end

      sha_new_tree = @github_client.create_tree( repo, blob_hash_array, {base_tree: sha_base_tree } ).sha
      commit_message = "Committed via MakerSpaceRepo!"
      sha_new_commit = @github_client.create_commit(repo, commit_message, sha_new_tree, sha_latest_commit).sha
      updated_ref = @github_client.update_ref(repo, ref, sha_new_commit)
    end

end

