# frozen_string_literal: true

module Api
  module V1
    # One row of GET /api/v1/spaces/:id/presence. Explicit allowlist (never
    # as_json/serializable_hash: the legacy dashboard leaked access_token and
    # student_id that way). The flags are computed in bulk by the controller.
    module PresenceUserSerializer
      module_function

      def call(user, avatar_url:, signed_safety_sheet:, membership_status:)
        {
          id: user.id, username: user.username, name: user.name, email: user.email,
          flagged: user.flagged, avatar_url: avatar_url,
          certifications: user.certifications.map do |c|
            { id: c.id, name: c.training_session&.training&.name_en || "Unknown" }
          end,
          signed_safety_sheet: signed_safety_sheet,
          membership_status: membership_status
        }
      end
    end
  end
end
