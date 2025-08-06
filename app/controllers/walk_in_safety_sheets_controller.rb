class WalkInSafetySheetsController < SessionsController
  before_action :signed_in

  # how many checkboxes should be sent
  NUMBER_OF_AGREEMENTS = 6

  # show a list of spaces to sign for
  def index
    @spaces = Space.where.associated(:space_managers)
  end

  def show
    @space = Space.find(params[:id]) # Space to sign entry for
    @walk_in_safety_sheet = WalkInSafetySheet.find_or_initialize_by(user: current_user, space: @space)
  end

  # User pressed 'sign sheet'
  def create
    # verify all checkboxes are checked
    unless params[:agreement] == ['1']*NUMBER_OF_AGREEMENTS
      render :show, status: :unprocessable_entity, notice: 'Please agree to all terms before signing'
      return
    end

    # then store contact details. Existence of record means all fields were accepted
    @walk_in_safety_sheet = WalkInSafetySheet.new(walk_in_safety_sheet_params.merge(user: current_user))
    if @walk_in_safety_sheet.save
      redirect_to action: :show
    end
  end

  def update
    # user pressed 'update contacts'
    @walk_in_safety_sheet = current_user.walk_in_safety_sheet
    if @walk_in_safety_sheet.update(walk_in_safety_sheet_params)
      redirect_to action: :show
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def walk_in_safety_sheet_params
    params.require(:walk_in_safety_sheet).permit(
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
      :emergency_contact_telephone,

      # we already have this
      #:supervisor_name,
      #:supervisor_telephone,
    )
  end
end
