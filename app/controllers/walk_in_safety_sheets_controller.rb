class WalkInSafetySheetsController < SessionsController
  before_action :signed_in

  def show
    #@walk_in_safety_sheet = WalkInSafetySheet.new
  end

  def create

  end

  private

  def walk_in_safety_sheet_params
    # NOTE: The actual checkboxes are not part of the form builder
    params.require(:walk_in_safety_sheet).permit(agreement: [])
  end
end
