class WalkInSafetySheetsController < SessionsController
  before_action :signed_in

  # show a list of spaces to sign for
  # NOTE: currently unused because the route is a singular route
  def index
    @walk_in_safety_sheet =
      WalkInSafetySheet.find_or_initialize_by(user: current_user)
    render :show
    #@spaces = Space.all
    #@signed_spaces = current_user.walk_in_safety_sheets.pluck(:space_id)
  end

  def new
    #@space = Space.find(params[:id]) # Space to sign entry for
    @walk_in_safety_sheet =
      WalkInSafetySheet.find_or_initialize_by(user: current_user)
  end

  # This also doubles as :new because this used to be a singular route...
  def show
    # FIXME: add spaces later
    #@space = Space.find(params[:id]) # Space to sign entry for
    @walk_in_safety_sheet =
      WalkInSafetySheet.find_or_initialize_by(user: current_user)
  end

  # User pressed 'sign sheet'
  def create
    @walk_in_safety_sheet =
      WalkInSafetySheet.new(
        walk_in_safety_sheet_params.merge(user: current_user)
      )

    # verify all checkboxes are checked
    unless params[:agreement] ==
             WalkInSafetySheetsController.complete_agreements
      render :show,
             status: :unprocessable_entity,
             notice: 'Please agree to all terms before signing'
      return
    end

    if @walk_in_safety_sheet.save
      render :show, status: :created # HTTP 201 reloads page
    else
      render :show, status: :unprocessable_entity
    end
  end

  # Update contacts
  def update
    # Only get user's sheets
    @walk_in_safety_sheet = current_user.walk_in_safety_sheets.find(params[:id])
    if @walk_in_safety_sheet.update(walk_in_safety_sheet_params)
      # The actual path is weird, we give the space ID instead
      redirect_to walk_in_safety_sheet_path(@walk_in_safety_sheet.space_id)
    else
      render :show, status: :unprocessable_entity
    end
  end

  def self.complete_agreements
    ['1'] * WalkInSafetySheet::NUMBER_OF_AGREEMENTS
  end

  private

  def walk_in_safety_sheet_params
    params.require(:walk_in_safety_sheet).permit(
      :space_id,
      :is_minor,
      #:participant_student_number,
      :participant_signature,
      #:participant_print_name,
      :participant_telephone_at_home,
      #:guardian_name,
      :guardian_signature,
      :minor_participant_name,
      :guardian_telephone_at_home,
      :guardian_telephone_at_work,
      # emergency_contact
      :emergency_contact_name,
      :emergency_contact_telephone
      # we already have this
      #:supervisor_name,
      #:supervisor_telephone,
    )
  end
end
