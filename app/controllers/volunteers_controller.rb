# frozen_string_literal: true
require 'googleauth'
require 'google/apis/calendar_v3'

class VolunteersController < ApplicationController
  layout 'volunteer'
  before_action :current_user
  before_action :grant_access, except: [:join_volunteer_program]
  before_action :grant_access_list, only: [:volunteer_list]
  def index
    @user = current_user
  end

  def emails
    @all_emails = User.volunteers.pluck(:email)
    @active_emails = User.volunteers.where(programs: {active: true}).pluck(:email)
    @unactive_emails = User.volunteers.where(programs: {active: false}).pluck(:email)
  end

  def volunteer_list
    @active_volunteers = User.volunteers.where(programs: {active: true})
    @unactive_volunteers = User.volunteers.where(programs: {active: false})
  end

  def join_volunteer_program
    if current_user.staff?
      flash[:notice] = 'You already have access to the Volunteer Area.'
    else
      Program.create(user_id: current_user.id, program_type: Program::VOLUNTEER, active: true)
      current_user.update(role: 'volunteer')
      flash[:notice] = "You've joined the Volunteer Program"
    end
    redirect_to volunteers_path
  end

  def my_stats
    volunteer_task_requests = current_user.volunteer_task_requests
    @processed_volunteer_task_requests = volunteer_task_requests.processed.approved.order(created_at: :desc).paginate(page: params[:page], per_page: 15)
    @certifications = current_user.certifications
    @remaining_trainings = current_user.remaining_trainings
  end

  def calendar

  end

  def new_event

  end

  def create_event
    if params[:space] == "makerspace" || params[:space] == "brunsfield"
      scope = 'https://www.googleapis.com/auth/calendar'

      authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open("#{Rails.root}/config/makerepo-1632742c49cc.json"),
        scope: scope)

      authorizer.fetch_access_token!

      service = Google::Apis::CalendarV3::CalendarService.new
      service.authorization = authorizer

      start_time = DateTime.parse(params[:datepicker_start]).strftime("%Y-%m-%dT%k:%M:00")
      end_time = DateTime.parse(params[:datepicker_end]).strftime("%Y-%m-%dT%k:%M:00")

      puts(start_time)
      puts(end_time)

      event = Google::Apis::CalendarV3::Event.new(
        summary: "#{current_user.name} Shadowing",
        start: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: start_time,
          time_zone: 'America/Toronto'
        ),
        end: Google::Apis::CalendarV3::EventDateTime.new(
          date_time: end_time,
          time_zone: 'America/Toronto'
        )
      )

      calendar_id = params[:space] == "makerspace" ? Rails.application.credentials[Rails.env.to_sym][:calendar][:makerspace] : Rails.application.credentials[Rails.env.to_sym][:calendar][:brunsfield]

      response = service.insert_event(calendar_id, event)

      if response.status != "cancelled"
        flash[:notice] = "The shadowing hour has been added"
      else
        flash[:alert] = "An hour occured"
      end

      redirect_to calendar_volunteers_path

    end
  end

  private

  def grant_access
    unless current_user.volunteer? || current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end

  def grant_access_list
    unless current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end
end
