# frozen_string_literal: true

class VolunteerTasksController < SessionsController
  include VolunteerTasksHelper
  include VolunteerAreaAccess
  skip_authorization only: :complete_task,
                     reason: "#{Authorization::ROLLOUT_PENDING}checked by task_owner_or_staff"
  before_action -> { @with_volunteer_header = true }
  before_action :staff_access, except: %i[show index my_tasks complete_task]
  before_action :volunteer_access, only: %i[show index my_tasks]
  before_action :signed_in, only: :complete_task
  before_action :task_owner_or_staff, only: :complete_task

  def index
    # Find all tasks that currently have an active volunteer assigned
    active_assigned_task_ids = VolunteerTaskJoin.joined
                                                .where(user_type: "Volunteer")
                                                .select(:volunteer_task_id)

    # 1. Available Tasks (Open tasks with NO active volunteer assigned)
    available_scope = VolunteerTask.where(status: "open")
                                   .where.not(id: active_assigned_task_ids)
                                   .includes(:space, :volunteer_task_joins, { require_trainings: :training }, responsible_staff_joins: :user)
                                   .order(created_at: :desc)

    # 2. Assigned Tasks (Open tasks WITH an active volunteer assigned)
    assigned_scope = VolunteerTask.where(status: "open")
                                  .where(id: active_assigned_task_ids)
                                  .includes(:space, :volunteer_task_joins, { require_trainings: :training }, responsible_staff_joins: :user)
                                  .order(created_at: :desc)

    # 3. Completed Tasks
    completed_scope = VolunteerTask.where(status: "completed")
                                   .includes(:space, :volunteer_task_joins, { require_trainings: :training }, responsible_staff_joins: :user)
                                   .order(updated_at: :desc)

    @pagy_available, @available_volunteer_tasks = pagy(available_scope, page_key: "page_available", limit: 50)
    @pagy_assigned, @assigned_volunteer_tasks   = pagy(assigned_scope, page_key: "page_assigned", limit: 50)
    @pagy_completed, @completed_volunteer_tasks = pagy(completed_scope, page_key: "page_completed", limit: 50)
  end

  def new
    @user = current_user
    @new_volunteer_task = VolunteerTask.new
    @tasks_categories ||= %w[Events Projects Supervising Workshops Other]
    @certifications = Training.all
    @spaces = Space.all.order(name: :asc)
  end

  def create
    @volunteer_task = VolunteerTask.new
    @volunteer_task.user_id = @user.try(:id)
    if save_task_with_photos(@volunteer_task)
      redirect_to volunteer_tasks_path, notice: "You've successfully created a new Volunteer Task"
    else
      redirect_to new_volunteer_task_path, alert: task_refusal(@volunteer_task)
    end
  end

  def show
    @volunteer_task = VolunteerTask.find(params[:id])
    @new_volunteer_join = VolunteerTaskJoin.new
    @new_required_training = RequireTraining.new
    @required_trainings = @volunteer_task.require_trainings
    trainings_already_added = @volunteer_task.require_trainings.pluck(:training_id)
    @trainings = Training.where.not(id: trainings_already_added).pluck(:name, :id)
    @trainings_already_added = Training.where(id: trainings_already_added).pluck(:name, :id)
    @user_trainings = user_trainings
    @volunteer_task_trainings = volunteer_task_trainings
    @volunteer_task_request = @volunteer_task
                                .volunteer_task_requests
                                .where(user_id: current_user.id)
                                .not_processed
                                .try(:last)

    @photos = @volunteer_task.photos.joins(:image_attachment)&.first(5) || []

    if current_user.staff?
      @volunteers = User.joins(:programs)
                        .where(programs: { program_type: Program::VOLUNTEER })
                        .where.not(id: joined_user_ids(@volunteer_task))
                        .pluck(:name, :id)
      @staff = User.where(role: %w[staff admin])
                   .where.not(id: joined_user_ids(@volunteer_task))
                   .pluck(:name, :id)
      @volunteers_in_task = User.joins(:programs)
                                .where(programs: { program_type: Program::VOLUNTEER }, id: joined_user_ids(@volunteer_task))
                                .pluck(:name, :id)
      @staff_in_task = User.where(role: %w[staff admin], id: joined_user_ids(@volunteer_task))
                           .pluck(:name, :id)
    end
  end

  def my_tasks
    @your_volunteer_tasks = current_user.get_volunteer_tasks_from_volunteer_joins
    @completed_task_requests = current_user.volunteer_task_requests
                                           .processed
                                           .approved
                                           .includes(volunteer_task: :space)
                                           .order(updated_at: :desc)
  end

  def complete_task
    volunteer_task = VolunteerTask.find(params[:id])
    volunteer_task.update(status: "completed")
    redirect_to my_tasks_volunteer_tasks_path
  end

  def edit
    @volunteer_task = VolunteerTask.find(params[:id])
    @tasks_categories = %w[Events Projects Supervising Workshops Other]
    @certifications = Training.all
    @volunteers_in_task = User.where(
      id: @volunteer_task.volunteer_task_joins.joined.where(user_type: "Volunteer").pluck(:user_id)
    )
    @staff_in_task = User.where(
      id: @volunteer_task.volunteer_task_joins.joined.where.not(user_type: "Volunteer").pluck(:user_id)
    )
    @staff_available = User.where(role: %w[staff admin])
                           .where.not(id: joined_user_ids(@volunteer_task))
    @volunteers_available = User.joins(:programs)
                                .where(programs: { program_type: Program::VOLUNTEER })
                                .where.not(id: joined_user_ids(@volunteer_task))
  end

  def update
    volunteer_task = VolunteerTask.find(params[:id])
    if save_task_with_photos(volunteer_task)
      redirect_to volunteer_tasks_path, notice: "Volunteer task updated"
    else
      redirect_to edit_volunteer_task_path(volunteer_task), alert: task_refusal(volunteer_task)
    end
  end

  def destroy
    volunteer_task = VolunteerTask.find(params[:id])
    if volunteer_task.destroy
      flash[:notice] = "Volunteer Task Deleted"
    else
      flash[:alert] = volunteer_task.errors.full_messages.to_sentence.presence || "Something went wrong"
    end
    redirect_to volunteer_tasks_path
  end

  private

  def joined_user_ids(task)
    task.volunteer_task_joins.joined.pluck(:user_id)
  end

  # The form's selects submit an empty value when nothing is chosen; those are not ids.
  def task_edit_params
    {
      certification_ids: submitted_ids(:certifications_id),
      joins: {
        add_staff: submitted_ids(:staff_id), add_volunteers: submitted_ids(:volunteer_id),
        remove_staff: submitted_ids(:remove_staff_id), remove_volunteers: submitted_ids(:remove_volunteer_id)
      }
    }
  end

  def submitted_ids(key)
    Array(params[key]).compact_blank
  end

  def task_owner_or_staff
    task = VolunteerTask.find(params[:id])
    return if current_user.staff? || (task.user_id.present? && task.user_id == current_user.id)

    flash[:alert] = "You cannot access this area."
    redirect_to root_path
  end

  # Saves the form and the posted photos together: when the form is refused or a photo is
  # refused, nothing is stored (a photo's reason is added to the task's errors).
  def save_task_with_photos(task)
    @volunteer_task = task
    saved =
      VolunteerTask.transaction do
        raise ActiveRecord::Rollback unless task.update_from_form(volunteer_task_params, by: current_user, **task_edit_params)

        update_photos
        true
      end
    saved == true
  rescue Photo::Refused => e
    task.errors.add(:base, "#{I18n.t('errors.volunteer.tasks.photos_refused')} #{e.message}")
    false
  end

  def task_refusal(task)
    task.errors.full_messages.to_sentence
  end

  # New photos (at most five) are added before any ticked one is removed, so a refused photo
  # leaves the existing photos untouched. The ticked photos are chosen first, so a new photo with
  # the same file name is not removed with them. Removing a photo deletes only its row here; Active
  # Storage deletes the stored file after the surrounding transaction has committed.
  def update_photos
    ticked = ticked_photos
    uploads = Array(params[:images]).first(5).reject(&:blank?)
    Photo.create_from_uploads!(uploads, volunteer_task_id: @volunteer_task.id)
    ticked.each(&:destroy)
  end

  def ticked_photos
    return [] if params[:deleteimages].blank?

    @volunteer_task.photos.select { |img| params[:deleteimages].include?(img.image.filename.to_s) }
  end

  def volunteer_task_params
    params.require(:volunteer_task).permit(
      :title,
      :description,
      :status,
      :space_id,
      :joins,
      :category,
      :cc,
      :hours
    )
  end
end
