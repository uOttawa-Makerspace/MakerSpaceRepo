# frozen_string_literal: true

module Api
  module V1
    # Who is in a space, sign in, sign out. Contract: doc/api/v1/presence.md.
    class PresenceController < BaseController
      before_action :require_staff!
      before_action :find_space

      def show
        users = SpacePresence.users_in(@space).order(:id)
                             .includes(certifications: { training_session: :training }).with_attached_avatar.to_a
        ids = users.map(&:id)
        signed = WalkInSafetySheet.where(user_id: ids).distinct.pluck(:user_id).to_set
        members = Membership.active.where(user_id: ids).pluck(:user_id).to_set

        render json: {
          space: SpaceSerializer.call(@space),
          users: users.map do |u|
            PresenceUserSerializer.call(u, avatar_url: avatar_url_for(u),
                                           signed_safety_sheet: signed.include?(u.id),
                                           membership_status: members.include?(u.id))
          end,
          current_user: { id: current_user.id }
        }
      end

      def create
        user = find_user!(params.require(:username))
        SpacePresence.sign_in(user, @space)
        head :no_content
      end

      def destroy
        SpacePresence.sign_out(find_user!(params[:username]), @space)
        head :no_content
      end

      private

      def find_space
        raise ActiveRecord::RecordNotFound unless params[:id].to_s.match?(/\A\d+\z/)

        @space = Space.find(params[:id])
      end

      # Case-insensitive, like every other username lookup; a NUL byte is no user.
      def find_user!(name)
        name = name.to_s
        user = name.include?("\0") ? nil : User.find_by_username(name)
        raise ActiveRecord::RecordNotFound if user.nil?

        user
      end

      def avatar_url_for(user)
        user.avatar.attached? ? rails_blob_url(user.avatar) : "#{request.base_url}/default-avatar.png"
      end
    end
  end
end
