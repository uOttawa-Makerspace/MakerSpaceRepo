class VideosController < ApplicationController
  before_action :set_video, only: [:download]

  def create
    @video = Video.create(video_params)
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
