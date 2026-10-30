require Rails.root.join("lib/jwt_authenticator")

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # D-EQ30: identify the user and reject everyone else. The rules are the
    # app's shared ones (lib/jwt_authenticator.rb), not reimplemented here:
    # - cookie session (browsers send it on the websocket handshake): not idle
    #   expired, user eligible (present, not deleted, active) and
    #   session[:token_version] == user.token_version (SessionAuthenticator);
    # - Bearer JWT (Authorization header, or a `token` query param for clients
    #   that cannot set headers; note URLs get logged): JwtAuthenticator.
    def connect
      self.current_user = session_user || token_user || reject_unauthorized_connection
    end

    private

    def session_user
      session = request.session
      return nil if session[:user_id].blank?

      user = User.find_by(id: session[:user_id])
      user if SessionAuthenticator.valid_for?(session, user)
    end

    def token_user
      header = request.headers["Authorization"].presence
      header ||= "Bearer #{request.params[:token]}" if request.params[:token].present?
      JwtAuthenticator.user_for(header) if header
    end
  end
end
