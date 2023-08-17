class StaffCertificationsController < StaffAreaController
  layout "staff_area"

  before_action :set_staff_certification, only: %i[update show]

  def create
    unless @user.staff_certification.nil?
      redirect_to user_path(@user.username),
                  alert: "You have already created a staff certification"
      return
    end

    @staff_certification = @user.build_staff_certification
    if @staff_certification.save
      redirect_to user_path(@user.username),
                  notice: "Successfully created staff certification"
    else
      redirect_to user_path(@user.username),
                  alert:
                    "Something went wrong while trying to create the staff certification"
    end
  end

  def update
    (1..StaffCertification::TOTAL_NUMBER_OF_FILES).each do |i|
      file_param = "pdf_file_#{i}"
      if params[file_param]
        if @staff_certification.send(file_param).attached?
          @staff_certification.send(file_param).purge
        end

        @staff_certification.attach_pdf_file(i, params[file_param])
      end
    end

    redirect_to user_path(@user.username),
                notice: "Successfully updated staff certifications"
  end

  private

  def set_staff_certification
    @staff_certification = StaffCertification.find(params[:id])
  end
end
