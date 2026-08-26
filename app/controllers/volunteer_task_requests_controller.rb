# frozen_string_literal: true

class VolunteerTaskRequestsController < SessionsController
  before_action -> { @with_volunteer_header = true }

  def index
    base_scope = if current_user.staff?
                   VolunteerTaskRequest.all
                 else
                   current_user.volunteer_task_requests
                 end

    @total_volunteers = User.volunteers.count

    # Exact total counts for KPI cards & tab badges
    @total_count     = base_scope.count
    @pending_count   = base_scope.not_processed.count
    @processed_count = base_scope.processed.count

    # Determine active tab (keeps processed tab open during pagination)
    @active_tab = if params[:tab].present?
                    params[:tab]
                  elsif params[:page_processed].present?
                    "processed"
                  else
                    "pending"
                  end

    pending_scope = base_scope
                      .not_processed
                      .includes(:user, volunteer_task: :space)
                      .filter_by_attribute(params[:search_pending])
                      .order(created_at: :desc)

    processed_scope = base_scope
                        .processed
                        .includes(:user, volunteer_task: :space)
                        .filter_by_attribute(params[:search_processed])
                        .order(updated_at: :desc)

    @pagy_pending, @pending_volunteer_task_requests = pagy(pending_scope, page_key: "page_pending", limit: 15)
    @pagy_processed, @processed_volunteer_task_requests = pagy(processed_scope, page_key: "page_processed", limit: 15)
  end

  def search_pending
    base_scope = if current_user.staff?
                   VolunteerTaskRequest.all
                 else
                   current_user.volunteer_task_requests
                 end

    scope = base_scope
              .not_processed
              .includes(:user, volunteer_task: :space)
              .filter_by_attribute(params[:search_pending])
              .order(created_at: :desc)

    @pagy_pending, @pending_volunteer_task_requests = pagy(scope, page_key: "page_pending", limit: 15)

    render partial: "volunteer_task_requests/pending_requests"
  end

  def search_processed
    base_scope = if current_user.staff?
                   VolunteerTaskRequest.all
                 else
                   current_user.volunteer_task_requests
                 end

    scope = base_scope
              .processed
              .includes(:user, volunteer_task: :space)
              .filter_by_attribute(params[:search_processed])
              .order(updated_at: :desc)

    @pagy_processed, @processed_volunteer_task_requests = pagy(scope, page_key: "page_processed", limit: 15)

    render partial: "volunteer_task_requests/processed_requests"
  end

  def create_request
    volunteer_task = VolunteerTask.find(params[:id])
    volunteer_task_request = VolunteerTaskRequest.new(
      volunteer_task_id: volunteer_task.id,
      user_id: current_user.id
    )

    if volunteer_task_request.save
      MsrMailer.send_notification_for_task_request(
        volunteer_task.id,
        volunteer_task_request.user_id
      ).deliver_later
      flash[:notice] = "You've sent a request. No further action is needed."
    else
      flash[:alert] = "Something went wrong. Please try it again."
    end
    redirect_back(fallback_location: root_path)
  end

  def update_approval
    volunteer_task_request = VolunteerTaskRequest.find(params[:id])
    if volunteer_task_request.update(approval: params[:approval])
      volunteer_task_join = volunteer_task_request.volunteer_task_join
      volunteer_task_join&.update(active: false)

      if volunteer_task_request.approval
        volunteer_task = volunteer_task_request.volunteer_task
        volunteer_id = volunteer_task_request.user_id
        volunteer = volunteer_task_request.user

        volunteer.update_wallet
        CcMoney.create_cc_money_from_approval(
          volunteer_task.id,
          volunteer_id,
          volunteer_task.cc
        )
        volunteer.update_wallet
        VolunteerHour.create_volunteer_hour_from_approval(
          volunteer_task.id,
          volunteer_id,
          volunteer_task.hours
        )
      end

      MsrMailer.send_notification_for_task_request_update(
        volunteer_task_request.id
      ).deliver_later
      flash[:notice] = "Task request updated."
    else
      flash[:alert] = "Something went wrong."
    end
    redirect_to volunteer_task_requests_path(tab: "pending")
  end
end
