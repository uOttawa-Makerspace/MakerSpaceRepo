class LicensesController < SessionsController

  skip_before_action :session_expiry, only: [:create]
  before_action :current_user, except: [:create, :new]

  layout "license"
 
  def common_creative_attribution
  end

  def common_creative_attribution_share_alike
  end

  def common_creative_attribution_no_derivatives
  end

  def common_creative_attribution_non_commercial
  end

  def attribution_non_commercial_share_alike
  end

  def attribution_non_commercial_no_derivatives
  end

  
end
