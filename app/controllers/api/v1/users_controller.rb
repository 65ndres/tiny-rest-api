class Api::V1::UsersController < ApplicationController
  def show
    if current_user
      render json: user_profile_json(current_user), status: :ok
    else
      render json: { error: "Unauthorized" }, status: :unauthorized
    end
  end

  # Account fields update the user; baby fields (baby_name, baby_birthdate,
  # nap count, day window) update the selected baby.
  def update
    unless current_user
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    attrs = user_params.to_h.symbolize_keys
    baby_attrs = attrs.extract!(*User::BABY_ATTRIBUTE_MAP.keys)
      .transform_keys { |key| User::BABY_ATTRIBUTE_MAP.fetch(key) }
    baby = current_baby

    saved = ActiveRecord::Base.transaction do
      current_user.assign_attributes(attrs)
      baby.assign_attributes(baby_attrs)
      user_valid = current_user.valid?
      baby_valid = baby.valid?
      raise ActiveRecord::Rollback unless user_valid && baby_valid

      current_user.save! && baby.save!
    end

    if saved
      render json: user_profile_json(current_user).merge(
        message: "Profile updated successfully"
      ), status: :ok
    else
      render json: {
        errors: (current_user.errors.full_messages + baby_error_messages(baby)).uniq
      }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    if current_user.cannot_delete_account_due_to_subscription?
      return render json: {
        error: "You must cancel your active subscription before deleting your account."
      }, status: :unprocessable_entity
    end

    token = request.headers["Authorization"]&.split&.last
    timestamp = Time.current.to_i

    current_user.transaction do
      current_user.update!(
        deleted_at: Time.current,
        email: "deleted_#{current_user.id}_#{timestamp}@example.invalid",
        username: "deleted_#{current_user.id}_#{timestamp}"
      )

      if token
        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        if payload["jti"]
          JwtDenylist.create!(
            jti: payload["jti"],
            exp: payload["exp"] ? Time.at(payload["exp"]) : Time.current + 1.hour
          )
        end
      end
    end

    render json: { message: "Account deleted" }, status: :ok
  rescue JWT::DecodeError, JWT::ExpiredSignature
    render json: { message: "Account deleted" }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def search
    query = params[:q]

    unless query.present?
      return render json: { error: "Search query is required" }, status: :bad_request
    end

    users = User.search_by_username(query)
      .where.not(id: current_user.id)
      .limit(20)

    render json: {
      users: users.map do |user|
        {
          id: user.id,
          username: user.username,
          first_name: user.first_name,
          last_name: user.last_name
        }
      end
    }, status: :ok
  end

  private

  def user_params
    params.require(:user).permit(
      :first_name,
      :last_name,
      :email,
      :username,
      :baby_name,
      :baby_birthdate,
      :daily_nap_count,
      :daily_nap_count_alt,
      :day_start_minutes,
      :day_end_minutes,
      :time_zone,
      :password,
      :password_confirmation
    )
  end

  def baby_error_messages(baby)
    baby.errors.map do |error|
      user_attribute = User::BABY_ATTRIBUTE_MAP.key(error.attribute)
      user_attribute ? User.new.errors.full_message(user_attribute, error.message) : error.full_message
    end
  end

  def user_profile_json(user)
    baby = current_baby
    {
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      username: user.username,
      subscription_type: user.subscription_type_for_payload,
      baby_id: baby.id,
      baby_name: baby.name,
      baby_birthdate: baby.birthdate&.iso8601,
      daily_nap_count: baby.daily_nap_count,
      daily_nap_count_alt: baby.daily_nap_count_alt,
      day_start_minutes: baby.day_start_minutes,
      day_end_minutes: baby.day_end_minutes,
      time_zone: user.time_zone
    }
  end
end
