# frozen_string_literal: true

require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "sub-model-#{SecureRandom.hex(8)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "submodel#{SecureRandom.hex(4)}"
    )
  end

  test "creating an active subscription expires prior active subscriptions" do
    basic = @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :active
    )

    pro = @user.subscriptions.create!(
      subscription_type: :pro,
      processor: :apple,
      amount: 9.99,
      currency: "usd",
      status: :active
    )

    basic.reload
    assert_equal "expired", basic.status
    assert_equal false, basic[:active]
    assert_equal true, pro.reload[:active]
    assert_equal "active", pro.status
    assert_equal 1, @user.subscriptions.active_subscriptions.count
    assert_equal pro, @user.active_subscription
  end

  test "mirrors boolean active from status" do
    sub = @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :active
    )
    assert_equal true, sub[:active]

    sub.update!(status: :cancelled)
    assert_equal false, sub[:active]
  end

  test "subscription_type_for_payload uses active subscription only" do
    @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :expired
    )
    @user.subscriptions.create!(
      subscription_type: :pro,
      processor: :apple,
      amount: 9.99,
      currency: "usd",
      status: :active
    )

    assert_equal "pro", @user.subscription_type_for_payload
    assert_equal "pro", @user.subscription_type
  end

  test "subscription_type_for_payload is nil without an active subscription" do
    @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :expired
    )

    assert_nil @user.subscription_type_for_payload
    assert_nil @user.active_subscription
  end

  test "database enforces at most one active subscription per user" do
    @user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 2.99,
      currency: "usd",
      status: :active
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      Subscription.insert_all!([
        {
          user_id: @user.id,
          processor: Subscription.processors[:apple],
          subscription_type: Subscription.subscription_types[:pro],
          amount: 9.99,
          currency: "usd",
          status: Subscription.statuses[:active],
          active: true,
          created_at: Time.current,
          updated_at: Time.current
        }
      ])
    end
  end
end
