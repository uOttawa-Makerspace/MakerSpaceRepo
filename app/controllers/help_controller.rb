class HelpController < SessionsController

  skip_before_action :session_expiry
  before_action :current_user

  layout "help"

  def main
  end

end
