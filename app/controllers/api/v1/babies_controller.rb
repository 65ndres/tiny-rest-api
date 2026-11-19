# frozen_string_literal: true

# Baby profiles on the signed-in account. One subscription covers every baby,
# but only Pro accounts can add more than one.
class Api::V1::BabiesController < ApplicationController
  before_action :set_baby, only: [ :update, :destroy ]

  # GET /api/v1/babies
  def index
    render json: { babies: babies_json }, status: :ok
  end

  # POST /api/v1/babies
  def create
    if current_user.babies.exists? && current_user.subscription_type_for_payload != "pro"
      return render json: {
        error: "Upgrade to Pro to add another baby.",
        code: "pro_required"
      }, status: :forbidden
    end

    baby = current_user.babies.build(baby_params)
    if baby.name.blank?
      return render json: { errors: [ "Name can't be blank" ] }, status: :unprocessable_entity
    end

    if baby.save
      render json: { baby: baby.as_api_json, babies: babies_json }, status: :created
    else
      render json: { errors: baby.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/babies/:id
  def update
    if @baby.update(baby_params)
      render json: { baby: @baby.as_api_json, babies: babies_json }, status: :ok
    else
      render json: { errors: @baby.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/babies/:id — removes the baby and all of its entries.
  def destroy
    if @baby.destroy
      render json: { babies: babies_json }, status: :ok
    else
      render json: { errors: @baby.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_baby
    @baby = current_user.babies.find_by(id: params[:id])
    return if @baby

    render json: { error: "Baby not found" }, status: :not_found
  end

  def baby_params
    params.require(:baby).permit(
      :name,
      :birthdate,
      :daily_nap_count,
      :daily_nap_count_alt,
      :day_start_minutes,
      :day_end_minutes
    )
  end

  def babies_json
    current_user.babies.reload.map(&:as_api_json)
  end
end
