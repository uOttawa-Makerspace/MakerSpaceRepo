# frozen_string_literal: true

module Api
  module V1
    # Contract: doc/api/v1/users.md.
    class UsersController < BaseController
      ASSIGNABLE_ROLES = %w[admin staff regular_user].freeze
      MIN_QUERY_LENGTH = 2
      MAX_QUERY_LENGTH = 100
      SEARCH_LIMIT = 50

      before_action :authenticate!
      before_action :require_staff!, only: %i[index programs]
      before_action :require_admin!, only: :role
      # After the auth filters, so an anonymous caller gets a 401 and does not consume a budget.
      rate_limit to: 60, within: 1.minute, only: :index, scope: "api-user-search",
                 by: -> { current_user.id }, with: :rate_limited

      # Self or staff. The record is resolved FIRST (the same case-insensitive lookup
      # as everywhere else) and authorization compares ids, never name strings: Ruby's
      # casecmp? folds Unicode ("maßen" == "massen") while the SQL lower() lookup does
      # not. A non-staff caller is refused for every other username, existing or not,
      # so the answer never reveals whether that user exists.
      def show
        staff = current_user.staff?
        # Staff may open soft-deleted accounts, like the legacy profile.
        user = staff ? User.unscoped { User.find_by_username(params[:username].to_s) } : User.find_by_username(params[:username].to_s)
        return render_error(:forbidden, "Not allowed", status: :forbidden) unless staff || user&.id == current_user.id

        raise ActiveRecord::RecordNotFound if user.nil?

        certifications = profile_certifications(user)
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

        if query.length > MAX_QUERY_LENGTH
          return render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                              fields: { query: ["is too long (maximum is #{MAX_QUERY_LENGTH} characters)"] })
        end

        found = User.text_search(User.sanitize_sql_like(query)).with_attached_avatar
                    .order(updated_at: :desc, id: :desc).limit(SEARCH_LIMIT + 1).to_a
        render json: {
          users: found.first(SEARCH_LIMIT).map { |u| UserSearchResultSerializer.call(u, avatar_url: avatar_url_for(u)) },
          meta: { limit: SEARCH_LIMIT, truncated: found.size > SEARCH_LIMIT }
        }
      end

      def role
        user = find_user!
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
        user = find_user!
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
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => e
        messages = e.record.errors.full_messages.presence || [e.message]
        render_error(:validation_failed, "Validation failed", status: :unprocessable_content,
                     fields: { programs: messages })
      end

      private

      LEVEL_RANK = { "Beginner" => 0, "Intermediate" => 1, "Advanced" => 2 }.freeze

      # Highest-level certification per training, whether earned in a training session
      # or only through a proficient project (the same trainings remaining_trainings
      # counts as held).
      def profile_certifications(user)
        from_sessions = user.certifications.includes(training_session: :training).highest_level
        held = from_sessions.to_set { |c| c.training_session.training_id }
        via_projects = user.certifications.where(training_session_id: nil)
                           .includes(proficient_project_session: { proficient_project: :training }).to_a
                           .select { |c| c.proficient_project_session&.proficient_project }
                           .group_by { |c| c.proficient_project_session.proficient_project.training_id }
                           .reject { |training_id, _| held.include?(training_id) }
                           .map { |_, certs| certs.max_by { |c| LEVEL_RANK.fetch(c.level, -1) } }
        from_sessions + via_projects
      end

      # Strict integer id: `find("12abc")` would silently mean 12.
      def find_user!
        raise ActiveRecord::RecordNotFound unless params[:id].to_s.match?(/\A\d+\z/)

        User.find(params[:id])
      end

      # Uploaded avatar -> its Active Storage URL; otherwise the bundled default image.
      def avatar_url_for(user)
        user.avatar.attached? ? rails_blob_url(user.avatar) : "#{request.base_url}/default-avatar.png"
      end
    end
  end
end
