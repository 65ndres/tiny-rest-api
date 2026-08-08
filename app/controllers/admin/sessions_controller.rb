module Admin
  class SessionsController < BaseController
    skip_before_action :authenticate_support_user!, only: %i[new create]

    def new
      redirect_to admin_root_path if current_support_user
    end

    def create
      email = params[:email].to_s.strip.downcase
      user = User.find_by('LOWER(email) = ?', email)

      if user.nil?
        flash.now[:alert] = 'No Support account found for that email. Run db:seed to create it.'
        render :new, status: :unprocessable_entity
      elsif !user.support_account?
        flash.now[:alert] = 'Only the Support account can sign in here.'
        render :new, status: :unprocessable_entity
      elsif !user.valid_password?(params[:password].to_s)
        flash.now[:alert] =
          'Wrong password. Use SUPPORT_USER_PASSWORD from your server .env (set when the user was seeded).'
        render :new, status: :unprocessable_entity
      else
        sign_in_support_user!(user)
        redirect_to admin_root_path, notice: 'Signed in.'
      end
    end

    def destroy
      sign_out_support_user!
      redirect_to admin_login_path, notice: 'Signed out.'
    end
  end
end
