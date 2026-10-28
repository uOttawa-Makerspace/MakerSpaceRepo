# frozen_string_literal: true

module Api
  module V1
    # Explicit allowlist of what a client may see of the signed-in user. Never
    # as_json/serializable_hash: a new column must not leak by default.
    module UserSerializer
      module_function

      def call(user)
        { id: user.id, username: user.username, name: user.name, role: user.role }
      end
    end
  end
end
