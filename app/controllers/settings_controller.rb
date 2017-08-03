class SettingsController < SessionsController

  before_action :current_user
  before_action :signed_in

  layout "setting"

  def profile
  end

  def admin
  	if github?
	    @client = github_client
	    @client_info = @client.user
	  end
  end

end
