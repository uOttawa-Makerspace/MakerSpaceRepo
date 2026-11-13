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
      flash[:notice] = I18n.t("volunteer_area.flash.program_already")
    else
      Program.join(current_user, Program::VOLUNTEER)
      flash[:notice] = I18n.t("volunteer_area.flash.program_joined")
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
    @proficient_projects_awarded = proc { |training| training.awarded_proficient_projects(current_user) }
    @learning_modules_completed = proc { |training| training.learning_modules_completed(current_user) }
    @recommended_hours = proc { |training, levels| training.recommended_hours(levels) }
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
    @shifts = current_user.shadowing_hours.complete.includes(:space).where('end_time > ?', DateTime.now)
    @all_shifts = ShadowingHour.complete.includes(:display_user, :space).where('end_time > ?', DateTime.now)
  end

  def delete_event
    shift = ShadowingHour.find_by(event_id: params[:event_id]) if params[:event_id].present?
    return refuse_shift(:shift_not_found) if shift.nil?

    case shift.cancel
    when :removed
      flash[:notice] = I18n.t("volunteer_area.flash.shift_cancelled")
      redirect_to calendar_volunteers_path
    when :gone then refuse_shift(:shift_not_found)
    else refuse_shift(:shift_not_removed)
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
      flash[:alert] = I18n.t("volunteer_area.flash.transcript_sign_in")
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

  # The shift is stored first, with the id its Google Calendar event will have, together with the record that the
  # event still has to be created. A job creates the event after that and is tried again until Google has it. If
  # the job cannot even be queued, the shift stays, the resend job queues it later, and the staff member is told.
  def create_shadowing_shift(user, space, start_time, end_time)
    change = nil
    ShadowingHour.transaction do
      shift = ShadowingHour.create!(
        user_id: user.id,
        start_time: start_time,
        end_time: end_time,
        event_id: SecureRandom.hex(16),
        space_id: space.id
      )
      change = GoogleCalendar::PendingChange.ask_shadow_push(shift.id)
    end

    if change.enqueue
      flash[:notice] = I18n.t("volunteer_area.flash.shift_added")
    else
      flash[:alert] = I18n.t('errors.volunteers.calendar_event_missing')
    end
  end

  def grant_access_list
    unless current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = I18n.t("volunteer_area.flash.no_access")
    end
  end
end
