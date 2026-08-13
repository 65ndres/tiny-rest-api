# frozen_string_literal: true

require "test_helper"

class Api::V1::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "sub-#{SecureRandom.hex(8)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "subuser#{SecureRandom.hex(4)}"
    )
    @token = Warden::JWTAuth::UserEncoder.new.call(@user, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  def active_customer_info(product_id: "tinyrest_pro_monthly")
    {
      "subscriptionsByProductIdentifier" => {
        product_id => {
          "isActive" => true,
          "store" => "APP_STORE",
          "price" => { "amount" => 9.99, "currency" => "USD" },
          "expiresDate" => 1.month.from_now.iso8601
        }
      }
    }
  end

  test "create_pro_subscription requires authentication" do
    post "/api/v1/subscription/create_pro_subscription",
         params: { customerInfo: active_customer_info },
         as: :json

    assert_response :unauthorized
  end

  test "create_pro_subscription creates pro and refresh_user returns pro" do
    basic = @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :active
    )

    assert_equal "basic", @user.subscription_type_for_payload

    assert_difference -> { @user.subscriptions.pro.count }, 1 do
      post "/api/v1/subscription/create_pro_subscription",
           params: { customerInfo: active_customer_info },
           headers: auth_headers(@token),
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body["success"]

    basic.reload
    assert_equal "expired", basic.status
    assert_equal false, basic[:active]
    assert_equal 1, @user.subscriptions.active_subscriptions.count
    assert_equal "pro", @user.reload.active_subscription.subscription_type

    get "/api/v1/auth/refresh-user", headers: auth_headers(@token)

    assert_response :success
    refresh_body = JSON.parse(response.body)
    assert_equal "pro", refresh_body.dig("user", "subscription_type")
  end

  test "create_pro_subscription leaves only one active when upgrading from basic" do
    @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :active
    )

    post "/api/v1/subscription/create_pro_subscription",
         params: { customerInfo: active_customer_info },
         headers: auth_headers(@token),
         as: :json

    assert_response :created
    assert_equal 1, @user.subscriptions.where(status: :active).count
    assert_equal 1, @user.subscriptions.where(active: true).count
  end

  test "create_pro_subscription creates only one row when multiple RC products are active" do
    customer_info = {
      "subscriptionsByProductIdentifier" => {
        "tinyrest_pro_monthly" => {
          "isActive" => true,
          "store" => "APP_STORE",
          "price" => { "amount" => 9.99, "currency" => "USD" },
          "expiresDate" => 1.month.from_now.iso8601
        },
        "tinyrest_pro_yearly" => {
          "isActive" => true,
          "store" => "APP_STORE",
          "price" => { "amount" => 49.99, "currency" => "USD" },
          "expiresDate" => 1.year.from_now.iso8601
        }
      }
    }

    assert_difference -> { @user.subscriptions.count }, 1 do
      post "/api/v1/subscription/create_pro_subscription",
           params: { customerInfo: customer_info },
           headers: auth_headers(@token),
           as: :json
    end

    assert_response :created
    assert_equal 1, @user.subscriptions.active_subscriptions.count
  end

  test "create_pro_subscription rejects when no active RevenueCat subscriptions" do
    post "/api/v1/subscription/create_pro_subscription",
         params: {
           customerInfo: {
             "subscriptionsByProductIdentifier" => {
               "tinyrest_pro_monthly" => { "isActive" => false }
             }
           }
         },
         headers: auth_headers(@token),
         as: :json

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal false, body["success"]
    assert_equal "No active subscriptions found", body["error"]
  end

  test "create_pro_subscription accepts active Pro entitlement without product subscriptions" do
    customer_info = {
      "subscriptionsByProductIdentifier" => {},
      "entitlements" => {
        "active" => {
          "Tiny Rest Pro" => {
            "identifier" => "Tiny Rest Pro",
            "isActive" => true,
            "store" => "APP_STORE",
            "expirationDate" => 1.month.from_now.iso8601
          }
        }
      }
    }

    assert_difference -> { @user.subscriptions.pro.count }, 1 do
      post "/api/v1/subscription/create_pro_subscription",
           params: { customerInfo: customer_info },
           headers: auth_headers(@token),
           as: :json
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal true, body["success"]
    assert_equal ["Tiny Rest Pro"], body["created_from"]
    assert_equal "pro", @user.reload.active_subscription.subscription_type
    assert @user.onboarding.reload.completed_at.present?
  end

  test "show returns the active subscription" do
    @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :expired
    )
    pro = @user.subscriptions.create!(
      subscription_type: :pro,
      processor: :apple,
      amount: 9.99,
      currency: "usd",
      status: :active
    )

    get "/api/v1/subscriptions", headers: auth_headers(@token)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal pro.id, body.dig("subscription", "id")
  end
end
