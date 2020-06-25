class VideosController < DevelopmentProgramsController
  include VideosHelper
  before_action :grant_access_admin
  before_action :set_video, only: %i[download destroy]

  def index
    @videos = Video.order(created_at: :desc)
  end

  def new
    @proficient_projects = ProficientProject.all.order(created_at: :asc).pluck(:title, :id)
    @new_video = Video.new
  end

  def create
    @video = Video.new(video_params)
    @video.direct_upload_url = ""
    if @video.save
      blob = @video.video.blob
      blob_size = bytes_to_megabytes(blob.byte_size)
      @video.update_attributes(
          video_file_name: blob.filename,
          video_file_size: blob_size,
          video_content_type: blob.content_type,
          video_updated_at: blob.created_at,
          processed: true
          )
      flash[:notice] = "Video Uploaded"
      redirect_to videos_path
    else
      flash[:alert] = "Something went wrong. Try again."
      redirect_to new_video_path
    end
  end

  def destroy
    @video.destroy
    flash[:notice] = 'Video Deleted.'
    redirect_to videos_path
  end

  private

  def set_video
    @video = Video.find(params[:id])
  end

  def video_params
    params.require(:video).permit(:video, :proficient_project_id)
  end

  def grant_access_admin
    unless current_user.admin?
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end
end
