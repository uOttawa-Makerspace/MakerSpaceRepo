# frozen_string_literal: true

module Api
  module V1
    # {id, name} of a space. Explicit allowlist: never keycode, max_capacity, etc.
    module SpaceSerializer
      module_function

      def call(space)
        { id: space.id, name: space.name }
      end
    end
  end
end
