# frozen_string_literal: true

class AnnouncementsController < StaffAreaController
  layout 'staff_area'
  before_action :set_announcement, only: %i[show edit]
  before_action :check_announcement, only: %i[create update destroy]

  def index
    @announcements = Announcement.all.where(public_goal: %w[volunteer staff]).order(created_at: :asc)
  end

  def new
    @announcement = Announcement.new
  end

  def show; end

  def edit; end

  def create
    @announcement.user_id = current_user.id
    if @announcement.save!
      redirect_to announcements_path
      flash[:notice] = "You've successfully created an announcement for #{@announcement.public_goal.capitalize}"
    end
  end

  def update
    if @announcement.update(announcement_params)
      flash[:notice] = 'Announcement updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to announcements_path
  end

  def destroy
    if @announcement.destroy
      flash[:notice] = 'Announcement Deleted'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to announcements_path
  end

  private

    def announcement_params
      params.require(:announcement).permit(:description, :public_goal, :active)
    end

    def set_announcement
      @announcement = Announcement.find(params[:id])
    end

    def check_announcement
      @announcement = Announcement.find_by(id: params[:id]) || Announcement.new(announcement_params)
      unless %w[volunteer staff].include?(@announcement.public_goal) || current_user.admin?
        flash[:alert] = "Please select another public goal"
        redirect_to new_announcement_path
      end
    end
end
