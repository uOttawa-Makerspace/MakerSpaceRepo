# frozen_string_literal: true

class Admin::AnnouncementsController < AdminAreaController
  layout "admin_area"

  def index
    @announcements = Announcement.all.order(created_at: :asc)
  end

  def new
    @announcement = Announcement.new
  end

  def show
    @announcement = Announcement.find(params[:id])
  end

  def edit
    @announcement = Announcement.find(params[:id])
  end

  def create
    announcement = Announcement.new(announcement_params)
    announcement.user_id = current_user.id
    if announcement.save!
      redirect_to admin_announcements_path
      flash[
        :notice
      ] = "You've successfully created an announcement for #{announcement.public_goal.capitalize}"
    end
  end

  def update
    announcement = Announcement.find(params[:id])
    flash_write(announcement, "announcements.not_updated", "Announcement updated") { announcement.update(announcement_params) }
    redirect_to admin_announcements_path
  end

  def destroy
    announcement = Announcement.find(params[:id])
    flash_write(announcement, "announcements.not_deleted", "Announcement Deleted", destroy: true) { announcement.destroy }
    redirect_to admin_announcements_path
  end

  private

  def announcement_params
    params.require(:announcement).permit(
      :description,
      :public_goal,
      :active,
      :end_date
    )
  end
end
