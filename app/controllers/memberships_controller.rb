class MembershipsController < SessionsController
  before_action :signed_in
  before_action only: :admin_create_membership do
    head :unauthorized unless current_user.admin?
  end
  before_action :no_container, only: :index

  def index
    load_membership_data
    @membership = current_user.memberships.new # for the purchase form

    @is_user_cutoff = is_user_cutoff
  end

  def your_memberships
    load_membership_data
    @membership = current_user.memberships.new # for the purchase form

    @is_user_cutoff = is_user_cutoff
  end
  
  def create
    return flash.now[:alert] = t('memberships.index.purchase.cutoff_tooltip') if is_user_cutoff

    @membership = current_user.memberships.new(membership_params)
    
    begin
      @membership.save!
      redirect_to @membership.checkout_link, allow_other_host: true
    rescue StandardError => e
      Rails.logger.error "Membership creation failed: #{e.message}"
      @membership.destroy if @membership.persisted?
      load_membership_data
      flash.now[:alert] = 'Error creating membership. Please try again.'
      render :index
    end
  end

  def admin_create_membership
    user = User.find(params[:user_id])
    days = params[:extend_days].to_i

    if days.positive?
      start_time = Membership.calculate_end_date(user)
      Membership.create!(
        user: user,
        membership_tier: MembershipTier.find_by!(title_en: "Custom Membership"),
        status: 'paid',
        start_date: start_time,
        end_date: start_time + days.days
      )
      flash[:notice] = "Custom membership added for #{days} days."
    else
      flash[:alert] = "Please enter a valid number of days."
    end

    redirect_back(fallback_location: memberships_path)
  end

  def revoke
    membership = Membership.find(params[:id])
    membership.update!(status: 'revoked')
    flash[:notice] = "Membership revoked successfully."
    redirect_back(fallback_location: memberships_path)
  end

  private

  def load_membership_data
    @memberships = current_user.memberships.where(status: 'paid').order(created_at: :desc)
    @active_memberships = current_user.memberships.active
  end
  
  def membership_params
    params.require(:membership).permit(:membership_tier_id)
  end

  def is_user_cutoff
    load_membership_data unless @active_memberships 

    latest_end_date = @active_memberships.maximum(:end_date)

    if latest_end_date
      one_year_from_today = Time.zone.today + 1.year

      candidates = [
        Date.new(one_year_from_today.year, 4, 30),
        Date.new(one_year_from_today.year, 8, 31),
        Date.new(one_year_from_today.year, 12, 31)
      ]

      candidates += [
        Date.new(one_year_from_today.year + 1, 4, 30),
        Date.new(one_year_from_today.year + 1, 8, 31),
        Date.new(one_year_from_today.year + 1, 12, 31)
      ]

      # find the earliest cutoff date that is >= one_year_from_today
      cutoff_date = candidates.select { |d| d >= one_year_from_today }.min

      latest_end_date >= cutoff_date
    else
      false
    end
  end
end
