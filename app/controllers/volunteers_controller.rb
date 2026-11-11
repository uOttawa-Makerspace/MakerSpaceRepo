# frozen_string_literal: true

require 'googleauth'
require 'google/apis/calendar_v3'

class VolunteersController < SessionsController
  include VolunteerAreaAccess

  skip_authorization only: %i[index join_volunteer_program transcript],
                     reason: "#{Authorization::ROLLOUT_PENDING}open to any signed-in user or checked inline"
  before_action :no_container, only: :index
  before_action :with_volunteer_header, except: :index
  before_action :current_user
  before_action :signed_in, only: :join_volunteer_program
  before_action :volunteer_access,
                except: %i[join_volunteer_program transcript],
                unless:
                  lambda {
                    controller_name == VolunteersController.controller_name &&
                      'index' == action_name
                  }

  before_action :grant_access_list,
                only: %i[emails populate_users volunteer_list create_event delete_event new_event]

  def index
    @user = current_user
    # A little bit special with headers and all
    render layout: 'application'
  end

  def emails
    @all_emails = User.volunteers.pluck(:email)
    @active_emails =
      User.volunteers.where(programs: { active: true }).pluck(:email)
    @unactive_emails =
      User.volunteers.where(programs: { active: false }).pluck(:email)
  end

  def volunteer_list
    base_scope = User.volunteers
                     .distinct
                     .includes(
                       :programs,
                       { volunteer_task_joins: :volunteer_task },
                       { certifications: [
                           { training_session: :training },
                           { proficient_project_session: { proficient_project: :training } }
                         ]
                       }
                     )
                     .order(name: :asc)

    # Load into memory arrays to avoid duplicate COUNT(*) and SELECT queries
    @active_volunteers = base_scope.where(programs: { active: true }).to_a
    @unactive_volunteers = base_scope.where(programs: { active: false }).to_a
  end

  def join_volunteer_program
    if current_user.staff?
      flash[:notice] = 'You already have access to the Volunteer Program.'
    else
      Program.join(current_user, Program::VOLUNTEER)
      flash[:notice] = "You've joined the Volunteer Program"
    end

    # Redirect to external HubSpot intake form
    redirect_to 'https://5oe8xl.share-na3.hsforms.com/20slW0brbQJCsdeEck-8vuQ', allow_other_host: true
  end

  def my_stats
    volunteer_task_requests = current_user.volunteer_task_requests
    scope = volunteer_task_requests.processed.approved.includes(:volunteer_task).order(created_at: :desc)
    @pagy, @processed_volunteer_task_requests = pagy(scope, limit: 15)
    @certifications = current_user.certifications.highest_level
    @remaining_trainings = current_user.remaining_trainings
    @skills = Skill.includes(trainings: [:proficient_projects, :learning_modules])
    @proficient_projects_awarded =
      Proc.new do |training|
        training.proficient_projects.where(
          id: current_user.order_items.awarded.pluck(:proficient_project_id)
        )
      end
    @learning_modules_completed =
      Proc.new do |training|
        training.learning_modules.where(
          id:
            current_user.learning_module_tracks.completed.pluck(
              :learning_module_id
            )
        )
      end
    @recommended_hours =
      Proc.new do |training, levels|
        training.learning_modules.where(level: levels).count +
          training.proficient_projects.where(level: levels).count
      end
  end

  def calendar
  end

  def populate_users
    json_data =
      User.volunteers.directory_search(params[:search]).select(:id, :name, :username)
    render json: { users: json_data }
  end

  def new_event
  end

  def shadowing_shifts
    @shifts = current_user.shadowing_hours.complete.where('end_time > ?', DateTime.now)
    @all_shifts = ShadowingHour.complete.includes(:display_user).where('end_time > ?', DateTime.now)
  end

  def delete_event
    shift = ShadowingHour.find_by(event_id: params[:event_id]) if params[:event_id].present?
    return refuse_shift(:shift_not_found) if shift.nil?

    if ShadowingHour.delete_event(shift.event_id, shift.space.name) == 'error'
      refuse_shift(:shift_not_removed)
    else
      shift.destroy!
      flash[:notice] = 'This shift has been cancelled.'
      redirect_to calendar_volunteers_path
    end
  end

  def create_event
    problem = shift_request_problem
    return refuse_shift(problem) if problem

    user = User.find(params[:user_id])
    return refuse_shift(:not_a_volunteer) unless user.volunteer?

    space = Space.where('LOWER(name) = ?', params[:space].downcase).first
    return refuse_shift(:space_not_found) if space.nil?

    create_shadowing_shift(
      user,
      space,
      shift_time(params[:datepicker_start]),
      shift_time(params[:datepicker_end])
    )
    redirect_to calendar_volunteers_path
  end

  def transcript
    unless signed_in?
      flash[:alert] = 'Please sign in to view your volunteer transcript.'
      redirect_to login_path and return
    end

    @volunteer = if params[:user_id].present? && (current_user.staff? || current_user.admin?)
                   User.find_by(id: params[:user_id]) || current_user
                 else
                   current_user
                 end

    @approved_task_requests = @volunteer.volunteer_task_requests
                                         .processed
                                         .approved
                                         .includes(volunteer_task: :space)
                                         .order(updated_at: :desc)
    @total_hours = @volunteer.get_total_hours
    @total_cc = @volunteer.get_total_cc
    @certifications = @volunteer.certifications.highest_level

    render layout: false
  end

  private

  SHADOWING_SPACES = ['makerspace', 'brunsfield centre'].freeze

  # The key (under errors.volunteers) of what is missing from a new shadowing shift request, or nil.
  def shift_request_problem
    if SHADOWING_SPACES.exclude?(params[:space])
      :no_space
    elsif shift_time(params[:datepicker_start]).nil? || shift_time(params[:datepicker_end]).nil?
      :no_dates
    elsif params[:user_id].blank?
      :no_user
    end
  end

  # The calendar's timestamp for a picked date and time, or nil when it is blank or not a date.
  def shift_time(value)
    DateTime.parse(value.to_s).strftime('%Y-%m-%dT%k:%M:00') if value.present?
  rescue Date::Error
    nil
  end

  # A shadowing shift request that was refused goes back to the calendar with the message for its cause.
  def refuse_shift(cause)
    flash[:alert] = I18n.t("errors.volunteers.#{cause}")
    redirect_to calendar_volunteers_path
  end

  # The shift is stored first, with the id its Google Calendar event will have, and the event is created
  # after that. If the calendar cannot be reached or refuses the event, the shift stays and the staff member is
  # told the calendar is missing it.
  def create_shadowing_shift(user, space, start_time, end_time)
    shift = ShadowingHour.create!(
      user_id: user.id,
      start_time: start_time,
      end_time: end_time,
      event_id: SecureRandom.hex(16),
      space_id: space.id
    )

    if create_calendar_event(shift, user, start_time, end_time)
      flash[:notice] = 'The shadowing shift has been added'
    else
      flash[:alert] = I18n.t('errors.volunteers.calendar_event_missing')
    end
  end

  # True when Google Calendar holds the shift's event; a failure is reported and answers false.
  def create_calendar_event(shift, user, start_time, end_time)
    event = ShadowingHour.create_event(start_time, end_time, user, params[:space], shift.event_id)
    event.status != 'cancelled'
  rescue StandardError => e
    HandledError.report(e, source: 'volunteers.create_shadowing_shift', shadowing_hour_id: shift.id)
    false
  end

  def grant_access_list
    unless current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end
end
