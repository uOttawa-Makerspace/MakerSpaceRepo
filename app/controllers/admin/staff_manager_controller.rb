class Admin::StaffManagerController < AdminAreaController
  def index
    @space_list = Space.all
  end
end
