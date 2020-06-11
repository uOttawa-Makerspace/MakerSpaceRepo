class VideosController < DevelopmentProgramsController
  before_action :grant_access_admin
  before_action :set_video, only: [:download, :destroy]

  def index
    @videos = Video.order(created_at: :desc)
  end

  def new
    @proficient_projects = ProficientProject.all.order(created_at: :asc).pluck(:title, :id)
  end

  def create
    @video = Video.new(video_params)
    @video.proficient_project_id = params["proficient_project_id"]
    @video.video_file_name = params["filename"]
    @video.video_file_size = params["filesize"]
    @video.video_content_type = params["filetype"]
    @video.video_updated_at = params["lastModifiedDate"]
    @video.save
  end

  def download
    redirect_to @video.video.expiring_url(30.seconds, :original)
  end

  def destroy
    @video.destroy
    flash[:notice] = "Video Deleted."
    redirect_to videos_path
  end

  private

  def set_video
    @video = Video.find(params[:id])
  end

  def video_params
    params.require(:video).permit(:direct_upload_url)
  end

  def grant_access_admin
    unless current_user.admin?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
