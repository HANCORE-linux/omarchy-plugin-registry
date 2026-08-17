module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      # Same trust rules as HTTP auth: expired or suspended sessions don't
      # get a socket either.
      def set_current_user
        session = Session.includes(:user).find_by(id: cookies.signed[:session_id])
        return nil if session.nil? || session.expired? || session.user.suspended_at.present?
        self.current_user = session.user
      end
  end
end
