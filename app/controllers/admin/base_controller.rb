module Admin
  class BaseController < ActionController::Base
    layout 'admin'

    protect_from_forgery with: :exception

    before_action :authenticate_support_user!

    helper_method :current_support_user

    private

    def current_support_user
      return @current_support_user if defined?(@current_support_user)

      @current_support_user =
        if session[:support_user_id]
          user = User.find_by(id: session[:support_user_id])
          user&.support_account? ? user : nil
        end
    end

    def authenticate_support_user!
      return if current_support_user

      redirect_to admin_login_path, alert: 'Please sign in with the Support account.'
    end

    def sign_in_support_user!(user)
      session[:support_user_id] = user.id
      @current_support_user = user
    end

    def sign_out_support_user!
      session.delete(:support_user_id)
      @current_support_user = nil
    end
  end
end
