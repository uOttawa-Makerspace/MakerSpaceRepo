class StaticPagesController < SessionsController

  before_action :current_user
  
  def home
  end

  def about
  end

  def contact
  end
  
end
