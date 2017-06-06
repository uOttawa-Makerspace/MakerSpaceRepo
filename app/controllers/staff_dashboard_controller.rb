class StaffDashboardController < ApplicationController

  before_action :current_user, :ensure_staff

  def index
  end


  def create_training_session
    @staff = current_user
    if params['training_session_name'].present? && params['training_session_time'].present?
      if !TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time']).present?
        TrainingSession.create(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time'])
        redirect_to (:back)
        flash[:notice] = "Training session created succesfully"
      else
        redirect_to (:back)
        flash[:alert] = "This training session already exists!"
      end
    else
      redirect_to (:back)
      flash[:alert] = "Enter a name!"
    end
  end


  def delete_training_session
    @staff = current_user
    if params['training_session_name'].present? && params['training_session_time'].present?
      if TrainingSession.find_by(name: params['training_session_name'], staff_id: @staff.id).present?
        TrainingSession.find_by(name: params['training_session_name'], staff_id: @staff.id).destroy
        redirect_to (:back)
        flash[:notice] = "Training session deleted succesfully"
      else
        redirect_to (:back)
        flash[:alert] = "No training session by that name!"
      end
    end
  end


  def add_trainee_to_training_session
    @staff = current_user
    if params['training_session_name'].present? && params['training_session_new_trainee'].present? && params['training_session_time'].present?
      if TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time']).present?
        @training_session = TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time'])
        #binding.pry
        if !@training_session[0].users.include? User.find(params['training_session_new_trainee'])
          @training_session[0].users << User.find(params['training_session_new_trainee'])
          redirect_to (:back)
          flash[:notice] = "User successfuly added to the training session"
        else
          redirect_to (:back)
          flash[:alert] = "User is already in this training session!"
        end
      else
        redirect_to (:back)
        flash[:alert] = "Invalid parameters!"
      end
    else
      redirect_to (:back)
      flash[:alert] = "Invalid parameters!"
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
