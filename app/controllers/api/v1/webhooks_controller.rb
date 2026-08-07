class Api::V1::WebhooksController < ApplicationController
  # skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  # RevenueCat webhook endpoint
  # POST /api/v1/webhooks/revenuecat
  def revenuecat
    event = params[:event]
    
    unless event
      return render json: { error: 'Missing event data' }, status: :bad_request
    end

    event_type = event['type']
    app_user_id = event.dig('app_user_id')
    
    unless app_user_id
      return render json: { error: 'Missing app_user_id' }, status: :bad_request
    end

    # Find user by app_user_id (assuming it's the user ID)
    user = User.find_by(id: app_user_id)
    
    unless user
      Rails.logger.warn("RevenueCat webhook: User not found for app_user_id: #{app_user_id}")
      return render json: { error: 'User not found' }, status: :not_found
    end

    # Process the webhook event
    result = process_revenuecat_event(user, event_type, event)
    
    if result[:success]
      render json: { success: true }, status: :ok
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("RevenueCat webhook error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    render json: { error: 'Webhook processing failed' }, status: :internal_server_error
  end

  private

  def process_revenuecat_event(user, event_type, event_data)
    case event_type
    when 'RENEWAL'
      handle_subscription_renewal(user, event_data)
    when 'CANCELLATION'
      handle_subscription_cancellation(user, event_data)
    when 'EXPIRATION'
      handle_subscription_expiration(user, event_data)
    when 'BILLING_ISSUE'
      handle_billing_issue(user, event_data)
    when 'UNCANCELLATION'
      handle_subscription_uncancellation(user, event_data)
    else
      Rails.logger.info("Unhandled RevenueCat event type: #{event_type}")
      { success: true } # Acknowledge but don't process
    end
  end

  def handle_subscription_renewal(user, event_data)
    subscription = find_subscription_for_event(user, event_data)
    return { success: false, error: 'Subscription not found' } unless subscription

    expiration_ms = event_data['expiration_at_ms']
    return { success: false, error: 'Missing expiration_at_ms' } unless expiration_ms.present?

    subscription.update!(
      expiration_date: Time.zone.at(expiration_ms.to_i / 1000.0).to_date
    )
    create_subscription_event(user, subscription, 'renewal', event_data['id'], event_data)
    { success: true }
  end

  def handle_subscription_cancellation(user, event_data)
    subscription = find_subscription_for_event(user, event_data)
    return { success: false, error: 'Subscription not found' } unless subscription

    subscription.update!(status: :cancelled, active: false)
    create_subscription_event(user, subscription, 'cancellation', event_data['id'], event_data)
    { success: true }
  end

  def handle_subscription_expiration(user, event_data)
    subscription = find_subscription_for_event(user, event_data)
    return { success: false, error: 'Subscription not found' } unless subscription

    subscription.update!(status: :expired, active: false)
    user.try(:token)&.destroy
    create_subscription_event(user, subscription, 'expiration', event_data['id'], event_data)
    { success: true }
  end

  def handle_billing_issue(user, event_data)
    subscription = find_subscription_for_event(user, event_data)
    return { success: false, error: 'Subscription not found' } unless subscription
    
    create_subscription_event(user, subscription, 'billing_issue', event_data['id'], event_data)
    { success: true }
  end

  def handle_subscription_uncancellation(user, event_data)
    subscription = find_subscription_for_event(user, event_data)
    return { success: false, error: 'Subscription not found' } unless subscription

    subscription.update!(status: :active, active: true)
    create_subscription_event(user, subscription, 'uncancellation', event_data['id'], event_data)
    { success: true }
  end

  def find_subscription_for_event(user, event_data)
    txn_id = event_data['original_transaction_id'].presence || event_data['transaction_id'].presence

    if txn_id.present?
      sub = user.subscriptions.find_by(processor_id: txn_id)
      return sub if sub
    end

    user.active_subscription || user.subscriptions.order(created_at: :desc).first
  end

  def create_subscription_event(user, subscription, event_type, processor_event_id, data)
    # Check if SubscriptionEvent model exists and create event
    if defined?(SubscriptionEvent)
      SubscriptionEvent.create!(
        user: user,
        subscription: subscription,
        event_type: event_type,
        processor_event_id: processor_event_id,
        data: data.to_json
      )
    end
  rescue StandardError => e
    Rails.logger.error("Failed to create subscription event: #{e.message}")
  end
end