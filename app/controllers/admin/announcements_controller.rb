# frozen_string_literal: true

class Admin::AnnouncementsController < AdminAreaController
  layout "admin_area"

  def index
    @announcements = Announcement.includes(:user).order(created_at: :asc)
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
    if announcement.save
      redirect_to admin_announcements_path,
                  notice: I18n.t("admin_pages.announcements.flash.created", audience: announcement.public_goal.capitalize)
    else
      redirect_to new_admin_announcement_path,
                  alert: validation_message(announcement, "errors.admin.announcements.not_created")
    end
  end

  def update
    announcement = Announcement.find(params[:id])
    flash_write(announcement, "announcements.not_updated", I18n.t("admin_pages.announcements.flash.updated")) { announcement.update(announcement_params) }
    redirect_to admin_announcements_path
  end

  def destroy
    announcement = Announcement.find(params[:id])
    flash_write(announcement, "announcements.not_deleted", I18n.t("admin_pages.announcements.flash.deleted"), destroy: true) { announcement.destroy }
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
