# frozen_string_literal: true

module Api
  module V1
    # Data for the new-session form. Same computation as Staff::TrainingSessionsController#new
    # (json). Contract: doc/api/v1/training_sessions.md.
    class TrainingSessionOptionsController < BaseController
      before_action :require_staff!

      # The legacy form always used the caller's space (assigned, else the first). An
      # explicit space_id picks another one the caller may work in; an unknown id is a 404.
      def show
        space = params[:space_id].present? ? requested_space : (current_user.space || Space.first)
        return if performed?
        raise ActiveRecord::RecordNotFound if space.nil?

        render json: {
          trainings: space.trainings.pluck(:id, :name_en),
          levels: TrainingSession.new.levels,
          course_names: CourseName.pluck(:name),
          instructors: User.where(role: %w[staff admin]).pluck(:id, :name),
          trainees: space.signed_in_users.pluck(:id, :name)
        }
      end

      private

      def requested_space
        space = Space.find(space_id_param)
        refuse_unworkable_space(space)
        space
      end

      def space_id_param
        raw = params[:space_id]
        raise ActiveRecord::RecordNotFound unless raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/)

        raw.to_i
      end
    end
  end
end
