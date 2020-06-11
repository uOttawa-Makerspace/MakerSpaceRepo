# frozen_string_literal: true

class VolunteerRequestsController < ApplicationController
  layout 'volunteer'
  before_action :grant_access, only: %i[index show]
  def index
    @total_volunteers = User.where(role: 'volunteer').count
    @all_volunteer_requests = VolunteerRequest.all.count
    @pending_volunteer_requests = VolunteerRequest.not_processed.order(created_at: :desc).paginate(page: params[:page], per_page: 15)
    @processed_volunteer_requests = VolunteerRequest.processed.order(created_at: :desc).paginate(page: params[:page], per_page: 15)
  end

  def create
    if !VolunteerRequest.find_by(user_id: current_user.id)
      @volunteer_request = VolunteerRequest.new(request_params)
      @volunteer_request.user_id = current_user.id
      flash[:notice] = "You've successfully submitted your volunteer request." if @volunteer_request.save!
    else
      flash[:notice] = 'You already requested to be a volunteer.'
    end
    redirect_to root_path
  end

  def show
    @volunteer_request = VolunteerRequest.find(params[:id])
    @user_request = @volunteer_request.user
    @certifications = @user_request.certifications
  end

  def update_approval
    volunteer_request = VolunteerRequest.find(params[:id])
    user = volunteer_request.user
    if volunteer_request.update(approval: params[:approval])
      if volunteer_request.approval == true
        user.update(role: 'volunteer')
        Skill.create(user_id: user.id, printing: volunteer_request.printing,
                     laser_cutting: volunteer_request.laser_cutting, virtual_reality: volunteer_request.virtual_reality,
                     embroidery: volunteer_request.embroidery, arduino: volunteer_request.arduino,
                     soldering: volunteer_request.soldering)
      else
        user.update(role: 'regular_user')
      end
      flash[:notice] = 'Volunteer Request updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to volunteer_requests_path
  end

  private

  def grant_access
    unless current_user.staff?
      flash[:alert] = 'You cannot access this area.'
      redirect_to root_path
    end
  end

  def request_params
    params.require(:volunteer_request).permit(:interests, :space_id, :printing, :arduino, :laser_cutting, :embroidery, :virtual_reality, :soldering)
  end
end
