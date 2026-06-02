# frozen_string_literal: true

class Api::V1::TimerRunsController < ApplicationController
  before_action :set_timer_run, only: [:update]

  # GET /api/v1/timer_runs
  # Optional query params: from, to (ISO8601 or YYYY-MM-DD), run_type
  def index
    timer_runs = current_user.timer_runs.submitted
    timer_runs = timer_runs.where(run_type: filter_run_type) if filter_run_type
    range = parse_range_params

    if range
      timer_runs = timer_runs
        .where('start_time < ? AND end_time >= ?', range[:end], range[:start])
        .order(start_time: :asc)
    else
      timer_runs = timer_runs.order(end_time: :desc)
    end

    render json: {
      timer_runs: timer_runs.map { |timer_run| serialize_timer_run(timer_run) }
    }, status: :ok
  end

  # GET /api/v1/timer_runs/active
  # Optional query param: run_type
  def active
    timer_runs = current_user.timer_runs.active
    timer_runs = timer_runs.where(run_type: filter_run_type) if filter_run_type
    timer_run = timer_runs.first

    render json: {
      timer_run: timer_run ? serialize_timer_run(timer_run) : nil
    }, status: :ok
  end

  # POST /api/v1/timer_runs
  def create
    start_time = parse_time_param(params[:start_time])
    unless start_time
      return render json: { error: 'start_time is required' }, status: :unprocessable_entity
    end

    run_type = params[:run_type].presence || TimerRun.run_types[:sleeping]
    unless TimerRun.run_types.value?(run_type)
      return render json: { error: 'invalid run_type' }, status: :unprocessable_entity
    end

    if bottle_submitted_create?(run_type)
      return create_bottle_feeding(start_time, run_type)
    end

    timer_run = current_user.timer_runs.build(
      start_time: start_time,
      run_type: run_type,
      metadata: metadata_param,
      submitted: false,
      active: true,
      paused: false
    )

    if timer_run.save
      render json: { timer_run: serialize_timer_run(timer_run) }, status: :created
    else
      render json: { errors: timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/timer_runs/:id
  def update
    if pause_resume_update?
      update_pause_state
    else
      submit_timer_run
    end
  end

  private

  def bottle_submitted_create?(run_type)
    run_type == TimerRun.run_types[:bottle] && boolean_param(:submitted)
  end

  def create_bottle_feeding(start_time, run_type)
    timer_run = current_user.timer_runs.build(
      start_time: start_time,
      end_time: start_time,
      duration: 0,
      run_type: run_type,
      metadata: metadata_param,
      submitted: true,
      active: false,
      paused: false
    )

    if timer_run.save
      render json: { timer_run: serialize_timer_run(timer_run) }, status: :created
    else
      render json: { errors: timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def filter_run_type
    return nil unless params[:run_type].present?

    run_type = params[:run_type].to_s
    return run_type if TimerRun.run_types.value?(run_type)

    nil
  end

  def metadata_param
    raw = params[:metadata]
    return {} if raw.blank?

    raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
  end

  def pause_resume_update?
    params.key?(:paused) && !boolean_param(:submitted)
  end

  def update_pause_state
    paused = boolean_param(:paused)

    if paused
      end_time = parse_time_param(params[:end_time])
      unless end_time
        return render json: { error: 'end_time is required when pausing' }, status: :unprocessable_entity
      end

      attrs = { paused: true, end_time: end_time }
    else
      attrs = { paused: false, end_time: nil }
    end

    attrs[:metadata] = metadata_param if params.key?(:metadata)

    @timer_run.assign_attributes(attrs)

    if @timer_run.save
      render json: { timer_run: serialize_timer_run(@timer_run) }, status: :ok
    else
      render json: { errors: @timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def submit_timer_run
    end_time = parse_time_param(params[:end_time])
    unless end_time
      return render json: { error: 'end_time is required' }, status: :unprocessable_entity
    end

    unless params[:duration].present?
      return render json: { error: 'duration is required' }, status: :unprocessable_entity
    end

    attrs = {
      end_time: end_time,
      duration: params[:duration].to_i,
      submitted: boolean_param(:submitted),
      paused: false
    }
    attrs[:metadata] = metadata_param if params.key?(:metadata)
    attrs[:start_time] = parse_time_param(params[:start_time]) if params[:start_time].present?

    @timer_run.assign_attributes(attrs)

    if @timer_run.save
      render json: { timer_run: serialize_timer_run(@timer_run) }, status: :ok
    else
      render json: { errors: @timer_run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def set_timer_run
    @timer_run = current_user.timer_runs.find_by(id: params[:id])
    return if @timer_run

    render json: { error: 'Timer run not found' }, status: :not_found
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def parse_time_param(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_range_params
    return nil unless params[:from].present? && params[:to].present?

    range_start = parse_range_boundary(params[:from], :start)
    range_end = parse_range_boundary(params[:to], :end)
    return nil unless range_start && range_end

    { start: range_start, end: range_end }
  end

  def parse_range_boundary(value, boundary)
    parsed = parse_time_param(value)
    return nil unless parsed

    return parsed if value.to_s.include?('T')

    boundary == :start ? parsed.beginning_of_day : parsed.end_of_day
  end

  def serialize_timer_run(timer_run)
    {
      id: timer_run.id,
      start_time: timer_run.start_time&.iso8601,
      end_time: timer_run.end_time&.iso8601,
      duration: timer_run.duration,
      submitted: timer_run.submitted,
      active: timer_run.active,
      paused: timer_run.paused,
      run_type: timer_run.run_type,
      metadata: timer_run.metadata
    }
  end
end
