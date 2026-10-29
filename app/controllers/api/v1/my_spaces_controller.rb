# frozen_string_literal: true

module Api
  module V1
    # The staff member's current space (users.space_id). Contract: doc/api/v1/spaces.md.
    class MySpacesController < BaseController
      before_action :require_staff!

      # Same default as the legacy dashboard (StaffAreaController#default_space):
      # the assigned space, else the first one; 404 when no space exists at all.
      def show
        space = current_user.space || Space.first
        raise ActiveRecord::RecordNotFound if space.nil?

        render json: SpaceSerializer.call(space)
      end

      def update
        raw = params.require(:space_id)
        unless raw.is_a?(Integer) || (raw.is_a?(String) && raw.match?(/\A\d{1,18}\z/))
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { space_id: ["must be a space id"] })
        end

        space = Space.find(raw)
        # update_columns: like change_space it stamps updated_at, but a stored profile
        # that fails a newer validation must not block switching space.
        current_user.update_columns(space_id: space.id, updated_at: Time.current)
        render json: SpaceSerializer.call(space)
      end
    end
  end
end
