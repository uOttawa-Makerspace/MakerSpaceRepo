# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/spaces.md.
    class SpacesController < BaseController
      before_action :require_staff!

      def index
        render json: Space.order(:name, :id).map { |s| SpaceSerializer.call(s) }
      end
    end
  end
end
