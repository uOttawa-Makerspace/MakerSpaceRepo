class Staff::CertificationsController < StaffDashboardController
  def update
    cert = Certification.find(params[:id])
    if cert.update(certification_params)
      flash[:notice] = 'Demotion completed.'
    else
      flash[:alert] = 'Something went wrong. Try again later.'
    end
    redirect_to user_path(cert.user.username)
  end

  def open_modal
    @certification_modal = Certification.find(params[:id])
    respond_to do |format|
      format.js
    end
  end

  private

  def certification_params
    params.require(:certification).permit(:active, :demotion_reason)
  end
end
