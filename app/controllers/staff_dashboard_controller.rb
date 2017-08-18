class StaffDashboardController < StaffAreaController
  before_action :default_space

  def index
  end

  private

  def default_space
    if @space.equal? nil
      if params['space_name'].present?
        @space = Space.find_by(name: params['space_name'])
      else
        @space = current_user.lab_sessions.last.space
      end
    else
      @space
    end
  end

end
