class Admin::TrainingSessionsController < AdminAreaController
  before_action :training_session_params, only: [:update]
  before_action :training_session, only: [:update, :destroy]

  layout 'staff_area'

  def index
  end

  def update
    @training_session.update(training_session_params)
    if @training_session.save
      flash[:notice] = "Updated Successfully"
      redirect_to :back
    else
      flash[:alert] = "Something went wrong"
      redirect_to :back
    end
  end


  def destroy
    if @training_session.destroy
        flash[:notice] = "Deleted Successfully"
    else
        flash[:alert] = "Something went wrong"
    end
    redirect_to :back
  end


  private

    def training_session
      @training_session = TrainingSession.find(params[:id])
    end

    def training_session_params
      params.require(:training_session).permit(:user_id).reject { |_, v| v.blank? }
    end

end
