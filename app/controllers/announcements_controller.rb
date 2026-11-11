# frozen_string_literal: true

class AnnouncementsController < StaffAreaController
  layout "staff_area"
  skip_authorization only: :dismiss, reason: "#{Authorization::ROLLOUT_PENDING}dismiss is outside the staff gate and only records the current user's own dismissal"
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
    return head(:unauthorized) unless signed_in?

    announcement = Announcement.find(params[:announcement_id])
    AnnouncementDismiss.dismiss(announcement, by: current_user)
    head :no_content
  end

  def edit
  end

  def create
    @announcement.user_id = current_user.id
    if @announcement.save
      redirect_to announcements_path,
                  notice: "You've successfully created an announcement for #{@announcement.public_goal.capitalize}"
    else
      redirect_to new_announcement_path,
                  alert: validation_message(@announcement, "errors.announcements.not_created")
    end
  end

  def update
    write_flash(@announcement, "errors.announcements.not_updated", "Announcement updated") { @announcement.update(announcement_params) }
    redirect_to announcements_path
  end

  def destroy
    write_flash(@announcement, "errors.announcements.not_deleted", "Announcement Deleted") { @announcement.destroy }
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
