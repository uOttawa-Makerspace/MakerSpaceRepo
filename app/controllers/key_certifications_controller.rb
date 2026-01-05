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
      (1..KeyCertification::TOTAL_NUMBER_OF_FILES).each do |i|
        file_param = "pdf_file_#{i}"
        if params[file_param]
          if @key_certification.send(file_param).attached?
            @key_certification.send(file_param).purge
          end

          @key_certification.attach_pdf_file(i, params[file_param])
        end
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
      file_number = params[:file_number].to_i
      file_attr = "pdf_file_#{file_number}"

      if @key_certification.send(file_attr).attached?
        @key_certification.send(file_attr).purge
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
