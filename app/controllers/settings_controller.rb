class SettingsController < SessionsController

  before_action :current_user
  before_action :signed_in

  layout "setting"

  def profile
    @programs = ProgramList.fetch_all
    @user_program = current_user.program.gsub("\n", "")
    @user_program = @user_program.gsub("\r", "")
  end

  def admin
  	if github?
	    @client = github_client
	    @client_info = @client.user
	  end
  end

end
