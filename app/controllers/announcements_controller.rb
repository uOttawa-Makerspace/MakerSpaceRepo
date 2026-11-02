# frozen_string_literal: true

class AnnouncementsController < StaffAreaController
  layout "staff_area"
  before_action :set_announcement, only: %i[show edit update destroy]
  before_action :build_announcement, only: :create
  before_action :ensure_announcement_access, only: %i[show edit]
  before_action :check_announcement, only: %i[create update destroy]

  def index
    @announcements =
      Announcement.all.where(public_goal: %w[volunteer]).order(created_at: :asc)
  end

  def new
    @announcement = Announcement.new
  end

  def show
  end

  def dismiss
    return head(:no_content) unless signed_in?

    AnnouncementDismiss.create(
      announcement_id: params[:announcement_id],
      user_id: current_user.id
    )
  end

  def edit
  end

  def create
    @announcement.user_id = current_user.id
    if @announcement.save!
      redirect_to announcements_path
      flash[
        :notice
      ] = "You've successfully created an announcement for #{@announcement.public_goal.capitalize}"
    end
  end

  def update
    if @announcement.update(announcement_params)
      flash[:notice] = "Announcement updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to announcements_path
  end

  def destroy
    if @announcement.destroy
      flash[:notice] = "Announcement Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to announcements_path
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

  def set_announcement
    @announcement = Announcement.find(params[:id])
  end

  def build_announcement
    @announcement = Announcement.new(announcement_params)
  end

  # Staff manage volunteer announcements only; admins manage every audience.
  def audience_allowed?(*goals)
    current_user.admin? || goals.compact.all? { |goal| goal == "volunteer" }
  end

  def ensure_announcement_access
    return if audience_allowed?(@announcement.public_goal)

    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end

  # Writes must hold for the stored audience and for any audience being requested.
  def check_announcement
    return if audience_allowed?(@announcement.public_goal,
                                params.dig(:announcement, :public_goal))

    flash[:alert] = "Please select another public goal"
    redirect_to new_announcement_path
  end
end
