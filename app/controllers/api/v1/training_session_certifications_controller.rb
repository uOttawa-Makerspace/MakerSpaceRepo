# frozen_string_literal: true

module Api
  module V1
    # Certify the trainees of a session. Same rules as
    # Staff::TrainingSessionsController#certify_trainees. Contract: doc/api/v1/training_sessions.md.
    class TrainingSessionCertificationsController < BaseController
      before_action :require_staff!

      def create
        session = TrainingSession.find(params[:training_session_id])
        unless current_user.admin? || session.user_id == current_user.id
          return render_error(:forbidden, "Not allowed", status: :forbidden)
        end

        certified = true
        session.users.each do |graduate|
          # A5 duplicate guard: skip anyone who already holds this training at this level.
          next if Certification.held_by(graduate.id, session.training_id, session.level).exists?

          certified = false unless Certification.new(user_id: graduate.id, training_session_id: session.id,
                                                     level: session.level).save
        end
        render json: { certified: certified }
      end
    end
  end
end
