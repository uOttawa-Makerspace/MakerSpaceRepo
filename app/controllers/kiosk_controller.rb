class KioskController < ApplicationController
  layout false, only: :show # no layout

  before_action :signed_in
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

    return head :unprocessable_content if space.nil?

    if params[:leaving]
      KioskSignEvent.sign_out(actor: current_user, visitor: visitor, space: space)
      flash[:notice] = "Signing out from #{space.name}, bye #{visitor.name}"
    elsif params[:entering]
      KioskSignEvent.sign_in(actor: current_user, visitor: visitor, space: space)
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
