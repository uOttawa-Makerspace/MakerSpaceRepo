class StaffDashboardController < ApplicationController
  before_action :current_user, :ensure_staff

  def index
  end

  def create_training_session
    @staff = current_user
    if params['training_session_name'].present?
      TrainingSession.create(name: params['training_session_name'], staff_id: @staff)
      redirect_to (:back)
      flash[:notice] = "Training session created succesfully"
    else
      redirect_to (:back)
      flash[:alert] = "Enter a name!"
    end
  end

  def bulk_add_certifications
    @staff = current_user
    if params['bulk_cert_users'].present? && params['bulk_certifications'].present?
      params['bulk_cert_users'].each do |user|
        if !User.find(user).certifications.where(name: params['bulk_certifications']).present?
          Certification.create(name: params['bulk_certifications'], user_id: user, staff_id: @staff.id)
        end
      end
      redirect_to (:back)
      flash[:notice] = "Certifications added succesfully!"
    else
      redirect_to (:back)
      flash[:alert] = "Invalid parameters!"
    end
  end

  private

  def ensure_staff
    unless staff?
      redirect_to '/' and return
    end
  end

end
