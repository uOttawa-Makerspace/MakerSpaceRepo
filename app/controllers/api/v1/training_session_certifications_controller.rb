# frozen_string_literal: true

module Api
  module V1
    # Certify the trainees of a session. Both this and
    # Staff::TrainingSessionsController#certify_trainees call TrainingSession#certify_trainees!. Contract: doc/api/v1/training_sessions.md.
    class TrainingSessionCertificationsController < BaseController
      before_action :require_staff!

      def create
        session = TrainingSession.find(params[:training_session_id])
        unless current_user.admin? || session.user_id == current_user.id
          return render_error(:forbidden, "Not allowed", status: :forbidden)
        end

        certified = session.certify_trainees!.certified?
        render json: { certified: certified }
      end
    end
  end
end
