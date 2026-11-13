# frozen_string_literal: true

class VolunteerTaskRequestsController < SessionsController
  before_action -> { @with_volunteer_header = true }
  include VolunteerAreaAccess

  before_action :signed_in, only: :update_approval
  before_action :volunteer_access, only: %i[index search_pending search_processed create_request]
  before_action :ensure_staff, only: :update_approval

  def index
    @volunteer_task_requests = if current_user.staff?
                                 VolunteerTaskRequest.all
                               else
                                 current_user.volunteer_task_requests
                               end
    @total_volunteers = User.volunteers.count

    # Exact total counts for KPI cards & tab badges
    @total_count     = @volunteer_task_requests.count
    @pending_count   = @volunteer_task_requests.not_processed.count
    @processed_count = @volunteer_task_requests.processed.count

    # Determine active tab (persists active tab on pagination)
    @active_tab = if params[:tab].present?
                    params[:tab]
                  elsif params[:page_processed].present?
                    "processed"
                  else
                    "pending"
                  end

    pending_scope = @volunteer_task_requests
                      .not_processed
                      .includes(:user, volunteer_task: :space)
                      .filter_by_attribute(params[:search_pending])
                      .order(created_at: :desc)

    processed_scope = @volunteer_task_requests
                        .processed
                        .includes(:user, volunteer_task: :space)
                        .filter_by_attribute(params[:search_processed])
                        .order(updated_at: :desc)

    @pagy_pending, @pending_volunteer_task_requests = pagy(pending_scope, page_key: "page_pending", limit: 15)
    @pagy_processed, @processed_volunteer_task_requests = pagy(processed_scope, page_key: "page_processed", limit: 15)
  end

  def search_pending
    @volunteer_task_requests = if current_user.staff?
                                 VolunteerTaskRequest.all
                               else
                                 current_user.volunteer_task_requests
                               end

    scope = @volunteer_task_requests
              .not_processed
              .includes(:user, volunteer_task: :space)
              .filter_by_attribute(params[:search_pending])
              .order(created_at: :desc)

    @pagy_pending, @pending_volunteer_task_requests = pagy(scope, page_key: "page_pending", limit: 15)

    render partial: "volunteer_task_requests/pending_requests"
  end

  def search_processed
    @volunteer_task_requests = if current_user.staff?
                                 VolunteerTaskRequest.all
                               else
                                 current_user.volunteer_task_requests
                               end

    scope = @volunteer_task_requests
              .processed
              .includes(:user, volunteer_task: :space)
              .filter_by_attribute(params[:search_processed])
              .order(updated_at: :desc)

    @pagy_processed, @processed_volunteer_task_requests = pagy(scope, page_key: "page_processed", limit: 15)

    render partial: "volunteer_task_requests/processed_requests"
  end

  def create_request
    volunteer_task = VolunteerTask.find(params[:id])
    unless volunteer_task.volunteer_task_joins.joined.exists?(user_id: current_user.id)
      flash[:alert] = I18n.t("volunteer_area.flash.request_not_assigned")
      return redirect_back(fallback_location: root_path)
    end
    if VolunteerTaskRequest
         .where(volunteer_task_id: volunteer_task.id, user_id: current_user.id)
         .where("approval IS NULL OR approval = ?", true)
         .exists?
      flash[:alert] = I18n.t("volunteer_area.flash.request_already_sent")
      return redirect_back(fallback_location: root_path)
    end
    volunteer_task_request = VolunteerTaskRequest.new(
      volunteer_task_id: volunteer_task.id,
      user_id: current_user.id
    )

    if volunteer_task_request.save
      MsrMailer.send_notification_for_task_request(
        volunteer_task.id,
        volunteer_task_request.user_id
      ).deliver
      flash[:notice] = I18n.t("volunteer_area.flash.request_sent")
    else
      flash[:alert] = validation_message(volunteer_task_request, "errors.volunteer.task_requests.not_created")
    end
    redirect_back(fallback_location: root_path)
  end

  def update_approval
    volunteer_task_request = VolunteerTaskRequest.find(params[:id])
    result = apply_approval(volunteer_task_request)

    case result
    when :already_approved
      flash[:notice] = I18n.t("volunteer_area.flash.request_already_approved")
    when :updated
      MsrMailer.send_notification_for_task_request_update(
        volunteer_task_request.id
      ).deliver
      flash[:notice] = I18n.t("volunteer_area.flash.request_updated")
    when :unchanged
      flash[:notice] = I18n.t("volunteer_area.flash.request_unchanged")
    else
      flash[:alert] = validation_message(volunteer_task_request, "errors.volunteer.task_requests.not_updated")
    end
    redirect_to volunteer_task_requests_path
  end

  private

  # Applies the staff decision under the request's row lock and says what happened. The award is paid inside
  # the lock; the caller sends mail afterwards, only when the approval really changed.
  def apply_approval(volunteer_task_request)
    volunteer_task_request.with_lock do
      next :already_approved if already_approved?(volunteer_task_request)
      next :failed unless volunteer_task_request.update(approval: params[:approval])

      award_approval(volunteer_task_request) if volunteer_task_request.approval
      volunteer_task_request.saved_change_to_approval? ? :updated : :unchanged
    end
  end

  def already_approved?(volunteer_task_request)
    volunteer_task_request.approval == true && ActiveModel::Type::Boolean.new.cast(params[:approval]) == true
  end

  # Completes the join and pays the volunteer's wallet and hours (see VolunteerTaskRequest#pay_award).
  def award_approval(volunteer_task_request)
    complete_join(volunteer_task_request)
    volunteer_task_request.pay_award
  end

  # Completes the requester's joined row. A row that ended after the lookup (the volunteer left at the
  # same moment) has nothing left to complete, and the approval carries on.
  def complete_join(volunteer_task_request)
    volunteer_task_request.volunteer_task_join&.finish!(:completed, by: current_user)
  rescue VolunteerTaskJoin::NotJoined
    nil
  end

  def ensure_staff
    if current_user.staff?
      record_authorization!(:staff)
      return
    end

    flash[:alert] = I18n.t("volunteer_area.flash.no_access")
    redirect_to root_path
  end
end
