# frozen_string_literal: true

class Api::V1::SleepPredictionsController < ApplicationController
  def show
    unless current_user
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    baby = current_baby
    submitted_runs = baby.timer_runs
      .submitted
      .where(run_type: TimerRun.run_types[:sleeping])
      .order(end_time: :desc)

    active_run = baby.timer_runs
      .active
      .where(run_type: TimerRun.run_types[:sleeping])
      .first

    prediction = SleepPredictionService.new(
      baby,
      submitted_runs: submitted_runs,
      active_run: active_run
    ).predict_with_range

    render json: prediction, status: :ok
  end
end
