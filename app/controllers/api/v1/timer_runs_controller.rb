# frozen_string_literal: true

class Api::V1::TimerRunsController < ApplicationController
  before_action :set_timer_run, only: [:update]

  # GET /api/v1/timer_runs
  def index
    timer_runs = current_user.timer_runs.submitted.order(end_time: :desc)

    render json: {
      timer_runs: timer_runs.map { |timer_run| serialize_timer_run(timer_run) }
    }, status: :ok
  end

  # POST /api/v1/timer_runs
  def create
    start_time = parse_time_param(params[:start_time])
    unless start_time
      return render json: { error: 'start_time is required' }, status: :unprocessable_entity
    end

    timer_run = current_user.timer_runs.build(
      start_time: start_time,
      submitted: false,
      active: true
    )

    if timer_run.save
      render json: { timer_run: serialize_timer_run(timer_run) }, status: :created
    else
      render json: { errors: timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/timer_runs/:id
  def update
    end_time = parse_time_param(params[:end_time])
    unless end_time
      return render json: { error: 'end_time is required' }, status: :unprocessable_entity
    end

    unless params[:duration].present?
      return render json: { error: 'duration is required' }, status: :unprocessable_entity
    end

    @timer_run.assign_attributes(
      end_time: end_time,
      duration: params[:duration].to_i,
      submitted: ActiveModel::Type::Boolean.new.cast(params[:submitted])
    )

    if @timer_run.save
      render json: { timer_run: serialize_timer_run(@timer_run) }, status: :ok
    else
      render json: { errors: @timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_timer_run
    @timer_run = current_user.timer_runs.find_by(id: params[:id])
    return if @timer_run

    render json: { error: 'Timer run not found' }, status: :not_found
  end

  def parse_time_param(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def serialize_timer_run(timer_run)
    {
      id: timer_run.id,
      start_time: timer_run.start_time&.iso8601,
      end_time: timer_run.end_time&.iso8601,
      duration: timer_run.duration,
      submitted: timer_run.submitted,
      active: timer_run.active
    }
  end
end
