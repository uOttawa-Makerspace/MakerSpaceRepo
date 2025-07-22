class Admin::CertificationsController < AdminAreaController
  before_action :set_certification, only: %i[update destroy]

  def show
    @certification = Certification.includes(:training_session).includes(:training).find(params[:id])
    @earner = User.find(@certification.user_id)
  end

  def update
    past_demotion_reason = @cert.demotion_reason
    if @cert.update(certification_params)
      user = @cert.user
      if @cert.active
        user.flag_message =
          user.flag_message.gsub(
            "; This user was demoted in '#{@cert.training.name_en}' because '#{past_demotion_reason}'",
            ""
          )
        user.flagged = false if user.flag_message.blank?
      else
        @cert.update(demotion_staff: @user)
        if user.flag_message.blank?
          user.flag_message =
            "; This user was demoted in '#{@cert.training.localized_name}' because '#{@cert.demotion_reason}'"
        else
          user.flag_message +=
            "; This user was demoted in '#{@cert.training.localized_name}' because '#{@cert.demotion_reason}'"
        end
        user.flagged = true
      end
      user.save
      flash[:notice] = "Action completed."
    else
      flash[:alert] = "Something went wrong. Try again later."
    end
    redirect_to @cert.active ? demotions_admin_certifications_path : user_path(@cert.user.username)
  end

  def destroy
    if @cert.destroy
      flash[:notice] = "Certification deleted. This action can't be undone"
    else
      flash[:alert] = "Something went wrong. Try again later."
    end
    redirect_to demotions_admin_certifications_path
  end

  def open_modal
    @certification_modal = Certification.find(params[:id])
    respond_to { |format| format.js }
  end

  def demotions
    search_params = params[:search]
    @demotions = Certification.filter_by_attribute(search_params)
    respond_to do |format|
      format.html
      format.js
    end
  end

  private

  def certification_params
    params.require(:certification).permit(:active, :demotion_reason)
  end

  def set_certification
    @cert = Certification.unscoped.find(params[:id])
  end
end
