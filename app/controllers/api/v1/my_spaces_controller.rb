# frozen_string_literal: true

module Api
  module V1
    # The staff member's current space (users.space_id). Contract: doc/api/v1/spaces.md.
    class MySpacesController < BaseController
      before_action :require_staff!

      # The saved space when the caller may work in it, else the first space they may work in
      # (User#current_space); { "space": null } when they have none.
      def show
        space = current_user.current_space
        render json: space ? SpaceSerializer.call(space) : { space: nil }
      end

      def update
        raw = params.require(:space_id)
        unless raw.is_a?(Integer) || (raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/))
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { space_id: ["must be a space id"] })
        end

        space = Space.find(raw)
        refuse_unworkable_space(space)
        return if performed?

        # update_columns: like change_space it stamps updated_at, but a stored profile
        # that fails a newer validation must not block switching space.
        current_user.update_columns(space_id: space.id, updated_at: Time.current)
        render json: SpaceSerializer.call(space)
      end
    end
  end
end
