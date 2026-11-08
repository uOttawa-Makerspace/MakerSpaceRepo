class KeyCertificationsController < SessionsController
  before_action :ensure_staff_or_teams_program
  before_action :set_key_certification, only: %i[update show destroy_pdf]

  def show
    if !@user.eql?(@key_certification.user) && !@user.admin?
      redirect_to users_path(@user.username),
                  alert: "You cannot access this page"
    end
  end

  def update
    if @user.eql?(@key_certification.user)
      KeyCertification::PDF_FILE_ATTACHMENTS.each do |number, param|
        next unless params[param]

        @key_certification.pdf_file_at(number).purge
        @key_certification.attach_pdf_file(number, params[param])
      end
    end

    respond_to do |format|
      format.html { redirect_back_or_to @user }
      format.json do
        render json: { message: "Successfully updated key certifications" }
      end
    end
  end

  def destroy_pdf
    if @user.eql?(@key_certification.user)
      attachment = @key_certification.pdf_file_at(params[:file_number].to_i)

      if attachment&.attached?
        attachment.purge
        flash[:notice] = "Successfully deleted certification"
      else
        flash[:alert] = "Couldn't find attached file"
      end
    end

    redirect_back(fallback_location: root_path)
  end

  private

  def set_key_certification
    @key_certification = KeyCertification.find(params[:id])
  end

  def ensure_staff_or_teams_program
    @user = current_user
    unless @user.staff? || @user.admin? ||
             @user.programs.pluck(:program_type).include?(Program::TEAMS)
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
