class RepositoriesController < SessionsController
  before_action :current_user
  before_action :signed_in, except: [:index]

  def index
    @repositories = Repository.all
  end

  def show
  end

  def new
    @client = github_client
    @repository = Repository.new
    @repository.photos.build
  end
  
  def edit
  end

  def create
    @repository = User.find(params[:user_id]).repositories.build(repository_params)
    if @repository.save
      render :show, notice: "successfully created repository!"
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

  private

    def repository_params
      params.require(:repository).permit(:title, :description, :category, :license, :user_id, :github)
    end

end
