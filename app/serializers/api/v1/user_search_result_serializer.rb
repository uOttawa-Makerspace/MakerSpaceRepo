# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/users?query=. Explicit allowlist (never as_json).
    module UserSearchResultSerializer
      module_function

      def call(user, avatar_url:)
        { id: user.id, username: user.username, name: user.name, email: user.email, avatar_url: avatar_url }
      end
    end
  end
end
