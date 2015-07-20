class MakesController < SessionsController
  before_action :current_user
  before_action :signed_in
  before_action :set_repository

  def create
    @repo = @repository.makes.build do |r|
      r.title = params[:repository][:title]
      r.description = params[:repository][:description]
      r.category = @repository.category
      r.license = @repository.license
      r.github = @repository.github
      r.github_url = @repository.github_url
      r.user_username = @user.username
      r.user_id = @user.id
    end

    if @repo.save
      create_photos
      copy_tags
      @repository.increment!(:make)
      render json: { redirect_uri: "#{repository_path(@user.username, @repo.slug)}" }
      @user.increment!(:reputation, 15)
    else
      render :new, alert: "Something went wrong"
    end

  end

  def new
    @repo = @repository.title
  end

  private
    
    def set_repository
      @repository = Repository.find_by(user_username: params[:user_username],slug: params[:slug])
    end

    def create_photos
      params['images'].each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, repository_id: @repo.id, width: dimension.first, height: dimension.last)
      end if params['images'].present?
    end

    def copy_tags
      @repository.tags.each do |t|
        Tag.create(name: t.name, repository_id: @repo.id)
      end
    end

end

