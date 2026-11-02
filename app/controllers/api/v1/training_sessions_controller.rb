# frozen_string_literal: true

module Api
  module V1
    # Training sessions run by the caller. Contract: doc/api/v1/training_sessions.md.
    class TrainingSessionsController < BaseController
      before_action :require_staff!

      # The caller's OWN sessions, also for admins (as the legacy index does).
      def index
        sessions = TrainingSession.where(user_id: current_user.id)
                                  .includes(:training, :space, :certifications, :users)
        render json: sessions.map { |s| TrainingSessionSerializer.call(s) }
      end

      def create
        input = CreateInput.new(params, current_user)
        return render_error(:forbidden, "Only an admin may choose another instructor", status: :forbidden) if input.foreign_instructor_denied?
        return render_input_errors(input.errors) unless input.valid?

        session = TrainingSession.new(input.attributes)
        course_name = CourseName.find_by(name: session.course)
        session.course_name = course_name if course_name
        session.save!
        render json: { id: session.id }, status: :created
      end

      private

      def render_input_errors(fields)
        render_error(:validation_failed, "Validation failed", status: :unprocessable_content, fields: fields)
      end

      # Parses and validates the create body; no database writes.
      class CreateInput
        attr_reader :errors

        def initialize(params, caller_user)
          @params = params
          @caller = caller_user
          @errors = {}
          @attributes = {}
        end

        # Staff can only name themselves; a different instructor is a 403, not a 422.
        def foreign_instructor_denied?
          raw = @params[:instructor_id]
          return false if raw.nil? || @caller.admin?

          integer(raw) != @caller.id
        end

        def valid?
          space = find_space
          training = find_training(space)
          level = check_level
          course = check_course
          instructor = find_instructor
          users = find_trainees
          return false if @errors.any?

          @attributes = { user: instructor, space: space, training: training, level: level,
                          course: course }
          @user_ids = users
          true
        end

        # Preloads avatars: the user model validates them when the join rows are saved.
        def attributes
          @attributes.merge(users: User.where(id: @user_ids).includes(:avatar_attachment).to_a)
        end

        private

        def error(field, message) = (@errors[field] ||= []) << message

        def integer(raw)
          return raw if raw.is_a?(Integer)

          raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/) ? raw.to_i : nil
        end

        def find_space
          id = integer(@params[:space_id])
          space = id && Space.find_by(id: id)
          error(:space_id, @params[:space_id].nil? ? "is required" : "must be an existing space") unless space
          space
        end

        def find_training(space)
          raw = @params[:training_id]
          return error(:training_id, "is required") if raw.nil?

          id = integer(raw)
          training = id && Training.find_by(id: id)
          return error(:training_id, "must be an existing training") unless training
          return training if space.nil? || space.trainings.exists?(training.id)

          error(:training_id, "is not offered in this space")
        end

        def check_level
          level = @params[:level]
          return error(:level, "is required") if level.nil?
          return level if level.is_a?(String) && TrainingSession.new.levels.include?(level)

          error(:level, "must be one of #{TrainingSession.new.levels.join(', ')}")
        end

        def check_course
          course = @params[:course]
          return nil if course.nil?
          return course if course.is_a?(String) && course.length <= 255

          error(:course, "must be a string of at most 255 characters")
        end

        def find_instructor
          raw = @params[:instructor_id]
          return @caller if raw.nil? || !@caller.admin?

          id = integer(raw)
          user = id && User.find_by(id: id)
          return user if user&.staff?

          error(:instructor_id, "must be a staff member")
        end

        def find_trainees
          raw = @params[:user_ids]
          return [] if raw.nil?
          return error(:user_ids, "must be a list of user ids") unless raw.is_a?(Array)

          ids = raw.map { |v| integer(v) }
          return error(:user_ids, "must be a list of user ids") if ids.any?(&:nil?)

          ids.uniq!
          missing = ids - User.where(id: ids).pluck(:id)
          return ids if missing.empty?

          error(:user_ids, "unknown user ids: #{missing.join(', ')}")
        end
      end
    end
  end
end
