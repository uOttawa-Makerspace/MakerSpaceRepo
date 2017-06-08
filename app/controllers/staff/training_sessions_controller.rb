class Staff::TrainingSessionsController < ApplicationController
  before_action :load_user, only: [:show, :edit, :update]

  layout 'staff_dashboard'

  def create_training_session
    @staff = current_user
    if !params['training_session_name'].present? || !Training.find_by(name: params['training_session_name']).present?
      flash[:alert] = "Please enter a valid training subject"
    elsif !params['training_session_time'].present?
      flash[:alert] = "Please choose a time slot"
    else
      TrainingSession.create(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time'])
      flash[:notice] = "Training session created succesfully"
    end
    redirect_to staff_training_sessions_url
  end

  def rename_training_session
    @staff = current_user
    if params['training_session_name'].present? &&
       params['training_session_time'].present? &&
       params['training_session_new_name'].present?
       if TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time']).present?
         @training_session = TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time'])[0]
         @training_session.name = params['training_session_new_name']
         @training_session.save
         redirect_to (:back)
         flash[:notice] = "Training session renamed succesfully"
       else
         redirect_to (:back)
         flash[:alert] = "No training session with the given parameters!"
       end
     else
       redirect_to (:back)
       flash[:alert] = "Invalid parameters!"
     end
  end

  # def delete_training_session
  #   @staff = current_user
  #   if params['training_session_name'].present? &&
  #      params['training_session_time'].present?
  #     if TrainingSession.find_by(name: params['training_session_name'], staff_id: @staff.id).present?
  #       TrainingSession.find_by(name: params['training_session_name'], staff_id: @staff.id).destroy
  #       redirect_to (:back)
  #       flash[:notice] = "Training session deleted succesfully"
  #     else
  #       redirect_to (:back)
  #       flash[:alert] = "No training session with the given parameters!"
  #     end
  #   end
  # end
  #
  # def add_trainee_to_training_session
  #   @staff = current_user
  #   if params['training_session_name'].present? &&
  #      params['training_session_new_trainee'].present? &&
  #      params['training_session_time'].present?
  #     if TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time']).present?
  #       @training_session = TrainingSession.where(name: params['training_session_name'], staff_id: @staff.id, session_time: params['training_session_time'])[0]
  #       if !@training_session.users.include? User.find(params['training_session_new_trainee'])
  #         @training_session.users << User.find(params['training_session_new_trainee'])
  #         redirect_to (:back)
  #         flash[:notice] = "User successfuly added to the training session"
  #       else
  #         redirect_to (:back)
  #         flash[:alert] = "User is already in this training session!"
  #       end
  #     else
  #       redirect_to (:back)
  #       flash[:alert] = "Invalid parameters!"
  #     end
  #   else
  #     redirect_to (:back)
  #     flash[:alert] = "Invalid parameters!"
  #   end
  # end


end
