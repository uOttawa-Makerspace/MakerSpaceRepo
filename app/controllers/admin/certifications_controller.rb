class Admin::CertificationsController < AdminAreaController
  before_action :set_certification, only: %i[update destroy]

  def update
    if @cert.update(certification_params)
      flash[:notice] = 'Action completed.'
    else
      flash[:alert] = 'Something went wrong. Try again later.'
    end
    @cert.active ? redirection = demotions_admin_certifications_path : redirection = user_path(@cert.user.username)
    redirect_to redirection
  end

  def destroy
    if @cert.destroy
      flash[:notice] = "Certification deleted. This action can't be undone"
    else
      flash[:alert] = 'Something went wrong. Try again later.'
    end
    redirect_to demotions_admin_certifications_path
  end

  def open_modal
    @certification_modal = Certification.find(params[:id])
    respond_to do |format|
      format.js
    end
  end

  def demotions
    @demotions = Certification.inactive
  end

  private

    def certification_params
      params.require(:certification).permit(:active, :demotion_reason)
    end

    def set_certification
      @cert = Certification.unscoped.find(params[:id])
    end
end
