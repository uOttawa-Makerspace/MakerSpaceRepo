class Admin::MembershipsController < AdminAreaController
  layout "admin_area"

  before_action :set_membership_tier, only: [:update]

  def index
    @membership_tiers = MembershipTier.order(:id)
  end

  def update
    if @membership_tier.update(membership_tier_params)
      flash[:success] = "Membership tier updated successfully."
    else
      flash[:alert] = @membership_tier.errors.full_messages.join(", ")
    end
    redirect_to admin_memberships_path
  end

  private

  def set_membership_tier
    @membership_tier = MembershipTier.find(params[:id])
  end

  def membership_tier_params
    params.require(:membership_tier).permit(
      :title_en,
      :title_fr,
      :internal_price,
      :external_price,
      :duration_seconds,
      :hidden
    )
  end
end
