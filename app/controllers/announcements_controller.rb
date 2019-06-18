class AnnouncementsController < ApplicationController
  def new
    @announcement = Announcement.new
  end

  def create
    @announcement = Announcement.new(announcement_params)
    @announcement.user_id = current_user.id
    if @announcement.save!
      redirect_to announcements_path
      flash[:notice] = "You've successfully created an announcement for #{@announement.public.capitalize}"
    end

  end

  def destroy

  end

  private

  def announcement_params
    params.require(:announcement).permit(:description, :public)
  end
end
