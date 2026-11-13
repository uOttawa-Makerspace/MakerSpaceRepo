# frozen_string_literal: true

class VolunteerHoursController < VolunteersController
  before_action :validate_user_for_editing, only: %i[edit update destroy]
  before_action :validate_unprocessed_for_owner, only: %i[edit update]
  before_action :validate_staff_for_request,
                only: %i[volunteer_hour_requests volunteer_hour_per_user update_approval]
  include VolunteerHoursHelper

  # The only decisions staff can record; anything else (missing, blank, other text) changes nothing.
  APPROVAL_VALUES = { "true" => true, "false" => false }.freeze

  def index
    @user = current_user
    scope = VolunteerHour.where(user_id: @user.id).includes(:volunteer_task).order(created_at: :desc)
    @pagy, @user_volunteer_hours = pagy(scope, limit: 50)
    @total_hours =
      calculate_hours(@user_volunteer_hours.approved.pluck(:total_time))
    load_new_hour_form
  end

  def new
    load_new_hour_form
  end

  def create
    @volunteer_hour = VolunteerHour.new(user_id: @user.try(:id))
    if @volunteer_hour.save_hand_logged(volunteer_hour_params)
      redirect_to volunteer_hours_path
      flash[:notice] = I18n.t("volunteer_area.flash.hours_sent")
    else
      redirect_to volunteer_hours_path,
                  alert: @volunteer_hour.errors.full_messages.to_sentence
    end
  end

  def edit
    @volunteer_hour = VolunteerHour.find(params[:id])
    @volunteer_tasks = task_options_for(@volunteer_hour.user_id, @volunteer_hour.volunteer_task_id)
    @hour, @minutes = (@volunteer_hour.total_time * 60).round.divmod(60)
  end

  def destroy
    volunteer_hour = VolunteerHour.find(params[:id])
    if !volunteer_hour.was_processed? || current_user.staff?
      destroy_hour(volunteer_hour)
    else
      flash[:alert] = I18n.t("errors.volunteer.hours.processed")
    end
    define_redirect(current_user)
  end

  def update
    volunteer_hour = VolunteerHour.find(params[:id])
    if volunteer_hour.save_hand_logged(volunteer_hour_params)
      flash[:notice] = I18n.t("volunteer_area.flash.hour_updated")
    else
      flash[:alert] = volunteer_hour.errors.full_messages.to_sentence
    end
    define_redirect(current_user)
  end

  def volunteer_hour_requests
    new_scope = VolunteerHour.not_processed.order(created_at: :desc)
    old_scope = VolunteerHour.processed.order(created_at: :desc)

    @pagy_new, @new_volunteer_hour_requests = pagy(new_scope, page_key: "new_page", limit: 15)
    @pagy_old, @old_volunteer_hour_requests = pagy(old_scope, page_key: "old_page", limit: 15)
    @total_volunteer_hour_requests = @new_volunteer_hour_requests.count
  end

  def update_approval
    volunteer_hour = VolunteerHour.find(params[:id])
    approval = APPROVAL_VALUES[params[:approval].to_s]
    if approval.nil?
      flash[:alert] = I18n.t("errors.volunteer.hours.approval_invalid")
    elsif volunteer_hour.update(approval: approval)
      flash[:notice] = I18n.t("volunteer_area.flash.hour_updated")
    else
      flash[:alert] = validation_message(volunteer_hour, "errors.volunteer.hours.approval_not_saved")
    end
    define_redirect(current_user)
  end

  def volunteer_hour_per_user
    total_hours_by_approval = VolunteerHour.group(:approval).sum(:total_time)
    @total_volunteer_hours_requested = VolunteerHour.sum(:total_time)
    @total_volunteer_hour_approved = total_hours_by_approval[true]
    @total_volunteer_hour_rejected = total_hours_by_approval[false]
    scope = User.volunteers.joins(:volunteer_hours).distinct
    @pagy, @users_with_volunteer_hours = pagy(scope, limit: 15)
    @total_volunteers = User.volunteers.count
  end

  private

  def destroy_hour(volunteer_hour)
    if volunteer_hour.destroy
      flash[:notice] = I18n.t("volunteer_area.flash.hour_deleted")
    else
      flash[:alert] = validation_message(volunteer_hour, "errors.volunteer.hours.not_deleted")
    end
  end

  def load_new_hour_form
    @new_volunteer_hour = VolunteerHour.new
    @volunteer_tasks = task_options_for(current_user.id)
  end

  # Title and id of the tasks the user is on or has completed, plus the task an existing hour already has.
  def task_options_for(user_id, current_task_id = nil)
    worked_on = VolunteerTaskJoin.worked_on.where(user_id: user_id).select(:volunteer_task_id)
    VolunteerTask
      .where(id: worked_on)
      .or(VolunteerTask.where(id: current_task_id))
      .order(created_at: :desc)
      .pluck(:title, :id)
  end

  def volunteer_hour_params
    permitted = %i[volunteer_task_id date_of_task total_time]
    permitted << :approval if current_user.staff?
    params.require(:volunteer_hour).permit(*permitted)
  end

  def validate_user_for_editing
    volunteer_hour = VolunteerHour.find(params[:id])
    if (current_user.id != volunteer_hour.user_id) && !current_user.staff?
      flash[:alert] = I18n.t("volunteer_area.flash.hour_edit_refused")
      redirect_to volunteer_hours_path
    end
  end

  def validate_unprocessed_for_owner
    return if current_user.staff?

    if VolunteerHour.find(params[:id]).was_processed?
      flash[:alert] = I18n.t("errors.volunteer.hours.processed")
      redirect_to volunteer_hours_path
    end
  end

  def validate_staff_for_request
    unless current_user.staff?
      flash[:alert] = I18n.t("volunteer_area.flash.hours_staff_only")
      redirect_to volunteer_hours_path
    end
  end
end
