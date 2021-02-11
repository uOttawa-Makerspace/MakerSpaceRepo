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

  def shadowing_shifts
    @shifts = current_user.shadowing_hours.where('end_time > ?', DateTime.now)
    @all_shifts = ShadowingHour.where('end_time > ?', DateTime.now).all
  end

  def delete_event
    if params[:event_id].present? && current_user.shadowing_hours.find_by(event_id: params[:event_id]).present?
      space = current_user.shadowing_hours.find_by(event_id: params[:event_id]).space.name
      event = ShadowingHour.delete_event(params[:event_id], space)

      if event != 'error'
        current_user.shadowing_hours.find_by(event_id: params[:event_id]).destroy!
        flash[:notice] = "This shift has been cancelled."
      else
        flash[:alert] = "An error occured while deleting the shift."
      end
    else
      flash[:alert] = "This shift has not been found."
    end
    redirect_to calendar_volunteers_path
  end

  def create_event
    if (params[:space] == "makerspace" || params[:space] == "brunsfield centre") && params[:datepicker_start].present? && params[:datepicker_end].present?

      start_time = DateTime.parse(params[:datepicker_start].to_s).strftime("%Y-%m-%dT%k:%M:00")
      end_time = DateTime.parse(params[:datepicker_end].to_s).strftime("%Y-%m-%dT%k:%M:00")

      event = ShadowingHour.create_event(start_time, end_time, current_user, params[:space])

      if event.status != "cancelled"
        ShadowingHour.create!(user_id: current_user.id, start_time: start_time, end_time: end_time, event_id: event.id, space_id: Space.where('LOWER(name) = ?', params[:space].downcase).first.id)
        flash[:notice] = "The shadowing shift has been added"
      else
        flash[:alert] = "An hour occurred"
      end
    else
      flash[:alert] = "An error occurred, please make sure you choose a space."
    end
    redirect_to calendar_volunteers_path
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
