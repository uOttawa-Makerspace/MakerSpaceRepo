class MembershipController < ApplicationController
  before_action :signed_in  
  def index
    @memberships = current_user.memberships.where(status: 'paid').order(created_at: :desc)
    @active_memberships = current_user.memberships.active
    @membership = current_user.memberships.new # for the purchase form
  end
  
  def create
    @membership = current_user.memberships.new(membership_params)
    
    begin
      if @membership.save
        redirect_to @membership.checkout_link, allow_other_host: true
      else
        load_membership_data
        render :index
      end
    rescue StandardError => e
      Rails.logger.error "Membership creation failed: #{e.message}"
      @membership.destroy if @membership.persisted?
      load_membership_data
      flash.now[:alert] = 'Error creating membership. Please try again.'
      render :index
    end
  end

  private

  def load_membership_data
    @memberships = current_user.memberships.where(status: 'paid').order(created_at: :desc)
    @active_memberships = current_user.memberships.active
  end
  
  def membership_params
    params.require(:membership).permit(:membership_type)
  end
end