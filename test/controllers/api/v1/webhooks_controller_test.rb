# frozen_string_literal: true

require "test_helper"

class Api::V1::WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @password = "password123"
    @user = User.create!(
      email: "revenuecat-webhook-#{SecureRandom.hex(8)}@example.com",
      password: @password,
      password_confirmation: @password
    )
    @txn_id = "2000001143694213"
    @subscription = @user.subscriptions.create!(
      processor: :apple,
      subscription_type: :pro,
      amount: 2.99,
      currency: "usd",
      processor_id: @txn_id,
      status: :active,
      expiration_date: Date.new(2026, 1, 1)
    )
  end

  test "RENEWAL updates subscription expiration_date from expiration_at_ms" do
    expiration_ms = 1_774_677_845_000

    post "/api/v1/webhooks/revenuecat",
         params: revenuecat_payload("RENEWAL", expiration_at_ms: expiration_ms),
         as: :json

    assert_response :success
    @subscription.reload
    assert_equal Time.zone.at(expiration_ms / 1000.0).to_date, @subscription.expiration_date
  end

  test "CANCELLATION sets subscription status to cancelled" do
    @subscription.update!(active: true)

    post "/api/v1/webhooks/revenuecat",
         params: revenuecat_payload("CANCELLATION"),
         as: :json

    assert_response :success
    assert @subscription.reload.cancelled?
    assert_equal false, @subscription[:active]
  end

  test "EXPIRATION sets subscription status to expired" do
    @subscription.update!(active: true)

    post "/api/v1/webhooks/revenuecat",
         params: revenuecat_payload("EXPIRATION"),
         as: :json

    assert_response :success
    assert @subscription.reload.expired?
    assert_equal false, @subscription[:active]
  end

  test "UNCANCELLATION sets subscription status to active" do
    @subscription.update!(status: :cancelled)

    post "/api/v1/webhooks/revenuecat",
         params: revenuecat_payload("UNCANCELLATION"),
         as: :json

    assert_response :success
    assert @subscription.reload.active?
    assert_equal true, @subscription[:active]
  end

  private

  def revenuecat_payload(type, overrides = {})
    event = base_event.merge("type" => type).merge(stringify_keys(overrides))
    { "api_version" => "1.0", "event" => event }
  end

  def base_event
    {
      "aliases" => [ @user.id.to_s ],
      "app_id" => "app3a80a76f44",
      "app_user_id" => @user.id.to_s,
      "country_code" => "US",
      "currency" => "USD",
      "entitlement_id" => nil,
      "entitlement_ids" => [ "Promsas Pro" ],
      "environment" => "SANDBOX",
      "event_timestamp_ms" => 1_774_677_549_260,
      "expiration_at_ms" => 1_774_677_845_000,
      "id" => "DDF2AE9C-CC28-40D5-B601-F0B6013DF829",
      "is_family_share" => false,
      "metadata" => nil,
      "offer_code" => nil,
      "original_app_user_id" => @user.id.to_s,
      "original_transaction_id" => @txn_id,
      "period_type" => "NORMAL",
      "presented_offering_id" => "new.offering",
      "price" => 2.99,
      "price_in_purchased_currency" => 2.99,
      "product_id" => "basic.montly.subscription",
      "purchased_at_ms" => 1_774_677_545_000,
      "renewal_number" => 1,
      "store" => "APP_STORE",
      "subscriber_attributes" => {},
      "transaction_id" => @txn_id
    }
  end

  def stringify_keys(hash)
    hash.transform_keys(&:to_s)
  end
end
