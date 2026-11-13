class KioskController < ApplicationController
  layout false, only: :show # no layout

  before_action :signed_in
  before_action :grant_access

  def index
    @spaces = current_user.workable_spaces.pluck(:name, :id)
  end

  def show
    @space = Space.find_by(id: params[:id])
    return redirect_to kiosk_index_path unless @space
    refuse_space unless current_user.can_work_in?(@space)
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
    return refuse_space unless current_user.can_work_in?(space)

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

  def refuse_space
    flash[:alert] = I18n.t("errors.staff.space_not_assigned")
    redirect_to kiosk_index_path
  end

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = "You cannot access this area."
      redirect_to root_path
    end
  end
end
