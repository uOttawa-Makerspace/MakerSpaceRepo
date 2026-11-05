# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/users/:username. Explicit allowlist (never as_json): no password,
    # access_token, student_id, wallet, etc. A new column is not exposed by default.
    module UserProfileSerializer
      module_function

      # certifications: Certification records (highest level per training);
      # remaining_trainings: Training records the user has no certification for.
      def call(user, avatar_url:, programs:, certifications:, remaining_trainings:)
        {
          user: {
            id: user.id, username: user.username, name: user.name, email: user.email,
            faculty: user.faculty, program: user.program, year_of_study: user.year_of_study,
            identity: user.identity, role: user.role, avatar_url: avatar_url,
            rfid: user.rfid && { card_number: user.rfid.card_number }
          },
          programs: programs,
          certifications: certifications.map do |cert|
            training = cert.training
            {
              id: cert.id, updated_at: cert.updated_at&.utc&.iso8601,
              training: training && { id: training.id, name_en: training.name_en }
            }
          end,
          remaining_trainings: remaining_trainings.map { |t| { id: t.id, name_en: t.name_en } }
        }
      end
    end
  end
end
