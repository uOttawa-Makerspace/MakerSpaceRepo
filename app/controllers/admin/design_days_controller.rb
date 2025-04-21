class Admin::DesignDaysController < AdminAreaController
  def show
    @design_day = DesignDay.instance
  end
end
