# frozen_string_literal: true

class Admin::TrainingSessionsController < AdminAreaController
  layout 'admin_area'
  before_action :training_session_params, only: [:update]
  before_action :training_session, only: %i[update destroy]

  def index

    # Preventing SQL Injection
    sort_array = ["created_at", "trainings.name", "users.name", "course", "count(training_sessions.id)", "count(users)"]

    if params[:sort_name].present? && params[:sort_name].to_i.between?(1, 6)
      if params[:sort_last].present? && params[:sort_last] == params[:sort_name]
        @sessions = TrainingSession.joins(:training, :user, "left join certifications on certifications.training_session_id = training_sessions.id").group('training_sessions.id', 'trainings.name', 'users.name').order("#{sort_array[params[:sort_name].to_i - 1]} ASC").paginate(:page => params[:page], :per_page => 20)
      else
        @sessions = TrainingSession.joins(:training, :user, "left join certifications on certifications.training_session_id = training_sessions.id").group('training_sessions.id', 'trainings.name', 'users.name').order("#{sort_array[params[:sort_name].to_i  - 1]} DESC").paginate(:page => params[:page], :per_page => 20)
        @last = params[:sort_name]
      end
    else
      @sessions = TrainingSession.all.paginate(:page => params[:page], :per_page => 20)
    end

    respond_to do |format|
      format.js
      format.html
    end

  end

  def update
    # TODO: check where this is being used?
    if @training_session.update(training_session_params)
      flash[:notice] = 'Updated Successfully'
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = 'Something went wrong'
      redirect_back(fallback_location: root_path)
    end
  end

  def destroy
    if @training_session.destroy
      flash[:notice] = 'Deleted Successfully'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_back(fallback_location: root_path)
  end

  private

    def training_session
      @training_session = TrainingSession.find(params[:id])
    end

    def training_session_params
      params.require(:training_session).permit(:user_id).reject { |_, v| v.blank? }
    end
end
