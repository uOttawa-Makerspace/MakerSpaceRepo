class KioskController < ApplicationController
  layout false, only: :show # no layout

  before_action :grant_access

  def index
    @spaces = Space.pluck(:name, :id)
  end

  def show
    @space = Space.find_by(id: params[:id])
    redirect_to kiosk_index_path unless @space
  end

  def edit
  end

  def sign_email
    # FIXME REMOVE ALL NOTICES, we dont show feedback here
    visitor = User.username_or_email(params[:visitor])
    space = Space.find_by(id: params[:kiosk_id])

    if visitor.nil?
      flash[:alert] = "User not found"
      redirect_to kiosk_path(params[:kiosk_id])
      return
    end

    head :unprocessable_entity if space.nil?

    # Get last session (if it exists)
    # session has not ended yet if last sign out time is in future
    last_session = LabSession.where(space: space).active_for_user(visitor).last
    if params[:leaving]
      # If last session hasn't ended yet, end it now.
      last_session.sign_out if last_session
      flash[:notice] = "Signing out from #{space.name}, bye #{visitor.name}"
    elsif params[:entering]
      # create unless last session is still active
      unless last_session
        LabSession.create(
          user: visitor,
          space_id: space.id,
          sign_in_time: Time.zone.now,
          sign_out_time: Time.zone.now + 8.hours
        )
      end
      flash[:notice] = "Signing in to #{space.name}, hello #{visitor.name}"
    end

    redirect_to kiosk_path(params[:kiosk_id])
  end

  private

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
