# frozen_string_literal: true

module Api
  module V1
    # One row of GET /api/v1/training_sessions. Explicit allowlist: the legacy JSON
    # sent whole training/space rows (Space#keycode) and whole certification rows.
    # The caller preloads training, space, certifications and users.
    module TrainingSessionSerializer
      module_function

      def call(session)
        {
          id: session.id, course: session.course, level: session.level,
          updated_at: session.updated_at.utc.iso8601,
          training: session.training && { id: session.training.id, name_en: session.training.name_en },
          space: session.space && SpaceSerializer.call(session.space),
          certifications: session.certifications.map { |c| { active: c.active, user_id: c.user_id } },
          users: session.users.map { |u| { id: u.id, username: u.username, name: u.name, email: u.email } }
        }
      end
    end
  end
end
