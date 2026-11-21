# frozen_string_literal: true

require "test_helper"

class Api::V1::BabiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "babies_api@example.com",
      password: "password123",
      password_confirmation: "password123",
      baby_name: "Ana",
      baby_birthdate: 6.months.ago.to_date
    )
    @other = User.create!(email: "babies_other@example.com", password: "password123")
    @token = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil).first
  end

  def auth_headers
    { "Authorization" => "Bearer #{@token}" }
  end

  def make_pro!
    @user.subscriptions.create!(subscription_type: :pro, processor: :apple, amount: 9.99,
                                currency: "usd", status: :active)
  end

  def json
    JSON.parse(response.body)
  end

  test "index requires authentication" do
    get "/api/v1/babies"

    assert_response :unauthorized
  end

  test "index lists the account's babies oldest first" do
    second = @user.babies.create!(name: "Bo")

    get "/api/v1/babies", headers: auth_headers

    assert_response :success
    assert_equal [ "Ana", "Bo" ], json["babies"].map { |b| b["name"] }
    assert_equal second.id, json["babies"].last["id"]
    assert json["babies"].first.key?("birthdate")
    assert json["babies"].first.key?("daily_nap_count")
  end

  test "create requires Pro once the account has a baby" do
    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies", params: { baby: { name: "Bo" } }, headers: auth_headers
    end

    assert_response :forbidden
    assert_equal "pro_required", json["code"]
  end

  test "Pro accounts can add a baby" do
    make_pro!

    assert_difference -> { @user.babies.count }, 1 do
      post "/api/v1/babies",
           params: { baby: { name: "Bo", birthdate: 2.months.ago.to_date.iso8601, daily_nap_count: 4 } },
           headers: auth_headers
    end

    assert_response :created
    assert_equal "Bo", json["baby"]["name"]
    assert_equal 4, json["baby"]["daily_nap_count"]
    assert_equal 2, json["babies"].length
  end

  test "create requires a name" do
    make_pro!

    post "/api/v1/babies", params: { baby: { name: " " } }, headers: auth_headers

    assert_response :unprocessable_entity
  end

  test "update edits a baby" do
    baby = @user.babies.first

    patch "/api/v1/babies/#{baby.id}",
          params: { baby: { name: "Ana Maria", daily_nap_count: 2 } },
          headers: auth_headers

    assert_response :success
    assert_equal "Ana Maria", baby.reload.name
    assert_equal 2, baby.daily_nap_count
  end

  test "update returns validation errors" do
    baby = @user.babies.first

    patch "/api/v1/babies/#{baby.id}",
          params: { baby: { birthdate: (Date.current + 2.days).iso8601 } },
          headers: auth_headers

    assert_response :unprocessable_entity
    assert json["errors"].present?
  end

  test "cannot update another account's baby" do
    patch "/api/v1/babies/#{@other.primary_baby.id}",
          params: { baby: { name: "Nope" } },
          headers: auth_headers

    assert_response :not_found
  end

  test "destroy removes the baby and its entries" do
    second = @user.babies.create!(name: "Bo")
    @user.timer_runs.create!(baby: second, start_time: 2.hours.ago, end_time: 1.hour.ago,
                             duration: 3_600_000, submitted: true)

    assert_difference -> { TimerRun.count }, -1 do
      delete "/api/v1/babies/#{second.id}", headers: auth_headers
    end

    assert_response :success
    assert_equal [ "Ana" ], json["babies"].map { |b| b["name"] }
  end

  test "cannot destroy the last baby" do
    delete "/api/v1/babies/#{@user.babies.first.id}", headers: auth_headers

    assert_response :unprocessable_entity
    assert_equal 1, @user.babies.count
  end

  # The app's Add baby screen sends the same fields as onboarding: name,
  # birthdate and the usual day window.
  def add_baby_params(overrides = {})
    {
      name: "Lorenzo",
      birthdate: 3.months.ago.to_date.iso8601,
      day_start_minutes: 480,
      day_end_minutes: 1290
    }.merge(overrides)
  end

  test "create requires authentication" do
    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies", params: { baby: add_baby_params }
    end

    assert_response :unauthorized
  end

  test "create saves the Add baby screen's profile" do
    make_pro!
    birthdate = 3.months.ago.to_date

    post "/api/v1/babies", params: { baby: add_baby_params }, headers: auth_headers

    assert_response :created
    baby = Baby.find(json["baby"]["id"])
    assert_equal @user.id, baby.user_id
    assert_equal "Lorenzo", baby.name
    assert_equal birthdate, baby.birthdate
    assert_equal 480, baby.day_start_minutes
    assert_equal 1290, baby.day_end_minutes
    assert_equal(
      { "id" => baby.id, "name" => "Lorenzo", "birthdate" => birthdate.iso8601,
        "daily_nap_count" => 3, "daily_nap_count_alt" => nil,
        "day_start_minutes" => 480, "day_end_minutes" => 1290 },
      json["baby"]
    )
    assert_equal [ "Ana", "Lorenzo" ], json["babies"].map { |b| b["name"] }
  end

  test "create trims the name" do
    make_pro!

    post "/api/v1/babies", params: { baby: add_baby_params(name: "  Lorenzo  ") }, headers: auth_headers

    assert_response :created
    assert_equal "Lorenzo", json["baby"]["name"]
  end

  test "create still accepts just a name from older app versions" do
    make_pro!

    post "/api/v1/babies", params: { baby: { name: "Bo" } }, headers: auth_headers

    assert_response :created
    assert_nil json["baby"]["birthdate"]
    assert_equal 3, json["baby"]["daily_nap_count"]
    assert_equal 570, json["baby"]["day_start_minutes"]
    assert_equal 1320, json["baby"]["day_end_minutes"]
  end

  test "create rejects a birthdate in the future" do
    make_pro!

    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies",
           params: { baby: add_baby_params(birthdate: (Date.current + 1.day).iso8601) },
           headers: auth_headers
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Birthdate must be in the past"
  end

  test "create accepts a baby born today" do
    make_pro!

    post "/api/v1/babies",
         params: { baby: add_baby_params(birthdate: Date.current.iso8601) },
         headers: auth_headers

    assert_response :created
  end

  test "create rejects a birthdate more than five years ago" do
    make_pro!

    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies",
           params: { baby: add_baby_params(birthdate: (5.years.ago.to_date - 1.day).iso8601) },
           headers: auth_headers
    end

    assert_response :unprocessable_entity
    assert_includes json["errors"], "Birthdate must be within the last 5 years"
  end

  test "create rejects a day that ends before it starts" do
    make_pro!

    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies",
           params: { baby: add_baby_params(day_start_minutes: 1200, day_end_minutes: 420) },
           headers: auth_headers
    end

    assert_response :unprocessable_entity
    assert json["errors"].present?
  end

  test "create rejects a name longer than the limit" do
    make_pro!

    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies",
           params: { baby: add_baby_params(name: "a" * (Baby::MAX_NAME_LENGTH + 1)) },
           headers: auth_headers
    end

    assert_response :unprocessable_entity
  end

  test "create always adds the baby to the signed-in account" do
    make_pro!

    assert_no_difference -> { @other.babies.count } do
      post "/api/v1/babies",
           params: { baby: add_baby_params.merge(user_id: @other.id) },
           headers: auth_headers
    end

    assert_response :created
    assert_equal @user.id, Baby.find(json["baby"]["id"]).user_id
  end

  test "a free account cannot add a second baby even with a full profile" do
    assert_no_difference -> { Baby.count } do
      post "/api/v1/babies", params: { baby: add_baby_params }, headers: auth_headers
    end

    assert_response :forbidden
    assert_equal "pro_required", json["code"]
  end

  test "a newly added baby can start a timer right away" do
    make_pro!
    post "/api/v1/babies", params: { baby: add_baby_params }, headers: auth_headers
    baby_id = json["baby"]["id"]

    post "/api/v1/timer_runs",
         params: { start_time: 1.minute.ago.iso8601, run_type: "sleeping" },
         headers: auth_headers.merge("X-Baby-Id" => baby_id.to_s)

    assert_response :created
    assert_equal baby_id, json["timer_run"]["baby_id"]
    assert_equal [ baby_id ], TimerRun.where(active: true, user: @user).pluck(:baby_id)
  end
end
