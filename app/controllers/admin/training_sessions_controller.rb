class Admin::TrainingSessionsController < ApplicationController
  before_action :target_training_session, only: [:update]
  before_action :training_session_params, only: [:update]

  layout 'admin_area'

  def update
    @training_session.update(training_session_params)
  end


  private

    def target_training_session
      @training_session = TrainingSession.find(params[:id])
    end

    def training_session_params
      params.require(:training_session_params).permit(:training_id, :user_id, :course, :users)
    end

end
