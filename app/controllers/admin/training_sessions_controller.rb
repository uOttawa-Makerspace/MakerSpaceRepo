# frozen_string_literal: true

class Admin::TrainingSessionsController < AdminAreaController
  layout 'admin_area'
  before_action :training_session_params, only: [:update]
  before_action :training_session, only: %i[update destroy]

  def index
    # Preventing SQL Injection
    sort_array = %w(training_sessions.created_at trainings.name users.name training_sessions.course count(certifications.id) count(users.id))

    # Checking if the params are in range of the array
    if params[:sort_name].present? && params[:sort_name].to_i.between?(1, 6)

      # Check if it's ASC or DESC
      if params[:sort_last].present? && params[:sort_last] == params[:sort_name]
        @sessions = TrainingSession.includes(:certifications, :users).joins(:training).
            group('trainings.name',
                  'users.name',
                  ['training_sessions.id', 'certifications.id'],
                  ['training_sessions.id', 'users.id']).
            order("#{sort_array[params[:sort_name].to_i  - 1]} ASC").
            references(:certifications, :users).
            paginate(:page => params[:page], :per_page => 20)
      else
        @sessions = TrainingSession.includes(:certifications, :users).joins(:training).
            group('trainings.name',
                  'users.name',
                  ['training_sessions.id', 'certifications.id'],
                  ['training_sessions.id', 'users.id']).
            order("#{sort_array[params[:sort_name].to_i  - 1]} DESC").
            references(:certifications, :users).
            paginate(:page => params[:page], :per_page => 20)

        # @last tells the view if the param DESC to switch it next time
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
