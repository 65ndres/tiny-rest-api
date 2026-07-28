# frozen_string_literal: true

class Api::V1::OnboardingController < ApplicationController
  before_action :set_onboarding

  # GET /api/v1/onboarding
  def show
    render json: { onboarding: onboarding_payload }, status: :ok
  end

  # PATCH /api/v1/onboarding
  def update
    step = params[:last_completed_step].presence || params.dig(:onboarding, :last_completed_step)

    unless step.present?
      return render json: { error: 'last_completed_step is required' }, status: :bad_request
    end

    unless Onboarding::STEPS.include?(step)
      return render json: {
        error: 'Invalid onboarding step',
        allowed_steps: Onboarding::STEPS
      }, status: :unprocessable_entity
    end

    @onboarding.update!(last_completed_step: step)
    render json: { onboarding: onboarding_payload }, status: :ok
  end

  # GET /api/v1/onboarding/completed_onboarding
  def completed_onboarding
    @onboarding.update!(
      completed_at: Time.current,
      last_completed_step: 'paywall'
    )
    render json: { onboarding: onboarding_payload }, status: :ok
  end

  private

  def set_onboarding
    return render json: { error: "Unauthorized" }, status: :unauthorized unless current_user

    @onboarding = current_user.onboarding
    return render json: { error: "Onboarding not found" }, status: :not_found unless @onboarding
  end

  def onboarding_payload
    {
      id: @onboarding.id,
      completed_at: @onboarding.completed_at,
      last_completed_step: @onboarding.last_completed_step,
      allowed_steps: Onboarding::STEPS
    }
  end
end
