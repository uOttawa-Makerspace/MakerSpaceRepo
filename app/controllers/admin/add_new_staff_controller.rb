class Admin::AddNewStaffController < AdminAreaController
  def index
    @space_list = Space.all
  end
end
