# frozen_string_literal: true

class Admin::TrainingSessionsController < AdminAreaController
  layout "admin_area"
  before_action :training_session_params, only: [:update]
  before_action :training_session, only: %i[update destroy]

  def index
    date_range = params[:date_range].presence || '30_days'
    @sessions = TrainingSession.filter_by_date_range(date_range)
                               .left_outer_joins(:training, :user)

    if params[:start_date].present? && params[:end_date].present?
      @sessions = @sessions.between_dates_picked(params[:start_date], params[:end_date])
    end

    if params[:training].present?
      @sessions = @sessions.by_training(params[:training])
    end

    if params[:trainers].present?
      @sessions = @sessions.by_trainers(params[:trainers])
    end

    @trainers = User.joins(:training_sessions).distinct.order(:name)

    if params[:course].present?
      @sessions = @sessions.by_course(params[:course])
    end

    if params[:status].present?
      @sessions = @sessions.by_status(params[:status])
    end

    if params[:search].present?
      @sessions = @sessions.filter_by_attribute(params[:search])
    end

    #pagination
    @sessions = @sessions.paginate(page: params[:page], per_page: 20)

    respond_to do |format|
      format.js
      format.html
    end
  end

  def update
    if @training_session.update(training_session_params)
      flash[:notice] = "Updated Successfully"
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = "Something went wrong"
      redirect_back(fallback_location: root_path)
    end
  end

  def destroy
    if @training_session.destroy
      flash[:notice] = "Deleted Successfully"
    else
      flash[:alert] = "Something went wrong"
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
