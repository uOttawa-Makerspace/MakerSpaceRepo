class Staff::TrainingSessionsController < ApplicationController
  before_action :load_user, only: [:show, :edit, :update]

  layout 'staff_dashboard'

  def create_training_session
    @staff = current_user
    if !params['training_session_name'].present? || !Training.find_by(name: params['training_session_name']).present?
      flash[:alert] = "Please enter a valid training subject"
    elsif !params['training_session_time'].present?
      flash[:alert] = "Please enter the training session's time slot"
    else
      @training_session = TrainingSession.new(training_id: Training.find_by(name: params['training_session_name']).id, user_id: @staff.id, timeslot: params['training_session_time'])
      if params['training_session_course'].present?
        @training_session.course = params['training_session_course']
      end
      @training_session.save
      flash[:notice] = "Training session created succesfully"
    end
    redirect_to staff_training_sessions_url
  end

  def rename_training_session
    @staff = current_user
    if !params['training_session_name'].present? || !Training.find_by(name: params['training_session_name']).present?
      flash[:alert] = "Please enter a valid training subject"
    elsif !params['training_session_time'].present?
      flash[:alert] = "Please enter the training session's time slot"
    elsif !params['training_session_new_name'].present? || !Training.find_by(name: params['training_session_new_name']).present?
      flash[:alert] = "Please select a valid new training subject"
    else
      @training_session = TrainingSession.where(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time'])[0]
      @training_session.training_id = Training.find_by(name: params['training_session_new_name']).id
      @training_session.save
      flash[:notice] =  "Training session renamed succesfully"
    end
    redirect_to (:back)
  end

  def reschedule_training_session
    @staff = current_user
    if !params['training_session_name'].present? || !Training.find_by(name: params['training_session_name']).present?
      flash[:alert] = "Please enter a valid training subject"
    elsif !params['training_session_time'].present?
      flash[:alert] = "Please enter the training session's time slot"
    elsif !params['training_session_new_time'].present?
      flash[:alert] = "Please enter the training session's new time slot"
    else
      @training_session = TrainingSession.where(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time'])[0]
      @training_session.timeslot = params['training_session_new_time']
      @training_session.save
      flash[:notice] =  "Training session rescheduled succesfully"
    end
    redirect_to (:back)
  end

  def delete_training_session
    @staff = current_user
    if params['training_session_name'].present? &&
       params['training_session_time'].present? &&
      if TrainingSession.find_by(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time']).present?
        TrainingSession.find_by(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time']).destroy
        flash[:notice] = "Training session deleted succesfully"
      else
        flash[:alert] = "No training session with the given parameters!"
      end
    end
    redirect_to (:back)

  end

  def add_trainees_to_training_session
    @staff = current_user
    if params['training_session_name'].present? &&
       params['training_session_new_trainees'].present? &&
       params['training_session_time'].present?
      if TrainingSession.where(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time']).present?
        @training_session = TrainingSession.where(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time'])[0]
        params['training_session_new_trainees'].each do |trainee|
          if !@training_session.users.include? User.find(trainee)
            @training_session.users << User.find(trainee)
            flash[:notice] = "User successfuly added to the training session"
          else
            flash[:alert] = "User is already in this training session!"
          end
        end
      else
        flash[:alert] = "Invalid parameters!"
      end
    else
      flash[:alert] = "Invalid parameters!"
    end
    redirect_to (:back)
  end

  def certify_trainees
    @staff = current_user
    if params['training_session_name'].present? &&
       params['training_session_graduates'].present? &&
       params['training_session_time'].present?
       if !Training.find_by(name: params['training_session_name']).present?
         flash[:alert] = "Training not found!"
       else
         @training_session = TrainingSession.where(training_id: Training.find_by(name: params['training_session_name']), user_id: @staff.id, timeslot: params['training_session_time'])[0]
         params['training_session_graduates'].each do |graduate|
           if @training_session.users.include? User.find(graduate)
             @certification = Certification.new(user_id: graduate, trainer_id: @staff.id, training: params['training_session_name'])
             @certification.save
             flash[:notice] = "Certified successfuly"
           end
         end
       end
     else
       flash[:alert] = "Invalid parameters!"
     end
     redirect_to (:back)
  end

end
