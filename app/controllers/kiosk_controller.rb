class KioskController < ApplicationController
  layout false, only: :show # no layout

  before_action :grant_access

  def index
    # BUG this isn't adequate, MTC doesn't have capacity
    # make a separate 'allowed' list, maybe a column in space?
    @spaces = Space.where.not(max_capacity: nil).pluck(:name, :id)
  end

  def show
    @space = Space.find_by(id: params[:id])
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

    if params[:leaving]
      # Sign out of space
      LabSession.where(user: visitor).last.update(sign_out_time: Time.zone.now)
      flash[
        :notice
      ] = "Signing out #{visitor.username} from kiosk #{space.name}"
    elsif params[:entering]
      # Sign in to space
      LabSession.create!(
        user: visitor,
        space_id: space.id,
        sign_in_time: Time.zone.now,
        sign_out_time: Time.zone.now + 8.hours
      )

      flash[:notice] = "Signing in "
    end
    # TODO maybe send email link instead?
    #send_sign_link params[:emal]
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
