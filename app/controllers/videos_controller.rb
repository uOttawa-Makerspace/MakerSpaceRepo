class VideosController < ApplicationController
  before_action :set_video, only: [:download]

  def index
    @videos = Video.all
  end

  def create
    @video = Video.new(video_params)
    @video.video_file_name = params["filename"]
    @video.video_file_size = params["filesize"]
    @video.video_content_type = params["filetype"]
    @video.video_updated_at = params["lastModifiedDate"]
    @video.save
  end

  def download
    redirect_to @video.video.expiring_url(30.seconds, :original)
  end

  private

  def set_video
    @video = Video.find(params[:id])
  end

  def video_params
    params.require(:video).permit(:direct_upload_url, :proficient_project_id)
  end
end
