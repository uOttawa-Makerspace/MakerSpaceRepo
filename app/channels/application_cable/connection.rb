module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    # D-EQ30: identify the user from the Rails session cookie (browsers send it
    # on the websocket handshake) and reject everyone else.
    # TODO(after A12 merges): also accept a Bearer JWT via
    # JwtAuthenticator.user_for(header). No client uses ActionCable with a JWT today.
    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user_id = request.session[:user_id]
      user = User.find_by(id: user_id) if user_id.present?
      user || reject_unauthorized_connection
    end
  end
end
