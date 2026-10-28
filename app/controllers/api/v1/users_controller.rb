# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/users.md.
    class UsersController < BaseController
      ASSIGNABLE_ROLES = %w[admin staff regular_user].freeze
      MIN_QUERY_LENGTH = 2
      SEARCH_LIMIT = 50

      before_action :authenticate!
      before_action :require_staff!, only: %i[index programs]
      before_action :require_admin!, only: :role
      # After the auth filters, so an anonymous caller gets a 401 and does not consume a budget.
      rate_limit to: 60, within: 1.minute, only: :index, scope: "api-user-search",
                 by: -> { current_user.id }, with: :rate_limited

      # Self or staff. A non-staff caller is refused for every other username
      # before any lookup, so the answer never reveals whether that user exists.
      def show
        username = params[:username].to_s
        unless current_user.staff? || current_user.username.casecmp?(username)
          return render_error(:forbidden, "Not allowed", status: :forbidden)
        end

        # Staff may open soft-deleted accounts, like the legacy profile.
        scope = current_user.staff? ? User.unscoped : User
        user = scope.find_by("lower(username) = ?", username.downcase) or raise ActiveRecord::RecordNotFound
        certifications = user.certifications.highest_level
        render json: UserProfileSerializer.call(
          user,
          avatar_url: avatar_url_for(user),
          programs: user.programs.pluck(:program_type),
          certifications: certifications,
          remaining_trainings: user.remaining_trainings.order(:id)
        )
      end

      def index
        query = params.require(:query).to_s.strip
        if query.length < MIN_QUERY_LENGTH
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { query: ["is too short (minimum is #{MIN_QUERY_LENGTH} characters)"] })
        end

        found = User.text_search(User.sanitize_sql_like(query)).with_attached_avatar
                    .order(:updated_at, :id).limit(SEARCH_LIMIT + 1).to_a
        render json: {
          users: found.first(SEARCH_LIMIT).map { |u| UserSearchResultSerializer.call(u, avatar_url: avatar_url_for(u)) },
          meta: { limit: SEARCH_LIMIT, truncated: found.size > SEARCH_LIMIT }
        }
      end

      def role
        user = User.find(params[:id])
        new_role = params.require(:role)
        unless new_role.is_a?(String) && ASSIGNABLE_ROLES.include?(new_role)
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { role: ["must be one of: #{ASSIGNABLE_ROLES.join(', ')}"] })
        end

        User.change_roles!([user.id], new_role, actor: current_user)
        head :no_content
      rescue User::LastAdminError => e
        render_error(:last_admin, e.message, status: :unprocessable_content, fields: { role: [e.message] })
      end

      def programs
        user = User.find(params[:id])
        flags = %i[development volunteer].index_with do |key|
          params.key?(key) or raise ActionController::ParameterMissing, key
          params[key]
        end
        invalid = flags.reject { |_, v| v == true || v == false }.keys
        if invalid.any?
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: invalid.index_with { ["must be true or false"] })
        end

        render json: { programs: user.sync_programs!(**flags) }
      end

      private

      # Uploaded avatar -> its Active Storage URL; otherwise the bundled default image.
      def avatar_url_for(user)
        user.avatar.attached? ? rails_blob_url(user.avatar) : "#{request.base_url}/default-avatar.png"
      end
    end
  end
end
