module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = rand(100)
    end

    private
      def find_verified_user
        Rails.logger.info cookies.encrypted["_session"]["user_id"]
        if verified_user = User.find_by(id: cookies.encrypted["_session"]["user_id"])
          verified_user
        else
        end
      end
  end
end
