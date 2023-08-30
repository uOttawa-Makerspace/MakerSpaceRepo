class KeyCertificationsController < StaffAreaController
  layout "staff_area"

  before_action :set_key_certification, only: %i[update show destroy_pdf]

  def show
    if !@user.eql?(@key_certification.user) && !@user.admin?
      redirect_to users_path(@user.username),
                  alert: "You cannot access this page"
    end
  end

  def update
    (1..KeyCertification::TOTAL_NUMBER_OF_FILES).each do |i|
      file_param = "pdf_file_#{i}"
      if params[file_param]
        if @key_certification.send(file_param).attached?
          @key_certification.send(file_param).purge
        end

        @key_certification.attach_pdf_file(i, params[file_param])
      end
    end

    redirect_to user_path(@user.username),
                notice: "Successfully updated key certifications"
  end

  def destroy_pdf
    file_number = params[:file_number].to_i
    file_attr = "pdf_file_#{file_number}"

    if @key_certification.send(file_attr).attached?
      @key_certification.send(file_attr).purge
      redirect_to key_certification_path(@key_certification.id),
                  notice: "Successfully deleted certification"
    else
      redirect_to key_certification_path(@key_certification.id),
                  alert: "Couldn't find attached file"
    end
  end

  private

  def set_key_certification
    @key_certification = KeyCertification.find(params[:id])
  end
end
