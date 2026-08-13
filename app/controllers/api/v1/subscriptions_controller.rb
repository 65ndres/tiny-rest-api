class Api::V1::SubscriptionsController < ApplicationController
  def status
    if current_user
      subscription = current_user.current_subscription

      response_data = {}
      if subscription
        response_data[:subscription] = {
          id: subscription.id,
          subscription_type: subscription.subscription_type_before_type_cast,
          amount: subscription.amount,
          currency: subscription.currency,
          created_at: subscription.created_at + 14.days
        }
      else
        response_data[:subscription] = nil
      end

      render json: response_data, status: :ok
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def show
    subscription = current_user.current_subscription
    render json: { subscription: subscription }, status: :ok
  end

  # Body: { app_user_id: "optional", receipt_data: {} }
  def validate
    unless current_user
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    app_user_id = params[:app_user_id] || current_user.id.to_s
    receipt_data = params[:receipt_data] || {}

    result = RevenuecatService.validate_purchase(
      current_user,
      app_user_id: app_user_id,
      receipt_data: receipt_data
    )

    if result[:success]
      render json: {
        success: true,
        subscription: {
          id: result[:subscription].id,
          subscription_type: result[:subscription].subscription_type,
          processor: result[:subscription].processor,
          amount: result[:subscription].amount,
          currency: result[:subscription].currency,
          created_at: result[:subscription].created_at
        },
        subscriber: result[:subscriber]
      }, status: :ok
    else
      render json: {
        success: false,
        error: result[:error]
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Purchase validation error: #{e.message}")
    render json: {
      success: false,
      error: 'Failed to validate purchase'
    }, status: :internal_server_error
  end

  # Sync subscription status from RevenueCat
  # POST /api/v1/subscription/sync
  def sync
    unless current_user
      return render json: { error: 'Unauthorized' }, status: :unauthorized
    end

    app_user_id = params[:app_user_id] || current_user.id.to_s

    subscriber_data = RevenuecatService.get_subscriber_info(app_user_id)

    unless subscriber_data
      return render json: {
        success: false,
        error: 'Failed to fetch subscriber info from RevenueCat'
      }, status: :unprocessable_entity
    end

    subscription = RevenuecatService.sync_subscription(
      current_user,
      subscriber_data,
      app_user_id
    )

    render json: {
      success: true,
      subscription: {
        id: subscription.id,
        subscription_type: subscription.subscription_type,
        processor: subscription.processor,
        amount: subscription.amount,
        currency: subscription.currency,
        created_at: subscription.created_at
      }
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error("Subscription sync error: #{e.message}")
    render json: {
      success: false,
      error: 'Failed to sync subscription'
    }, status: :internal_server_error
  end

  def create_basic_subscription
    subscription = current_user.subscriptions.create!(
      subscription_type: :basic,
      processor: :apple,
      amount: 299.0,
      currency: 'usd',
      status: :active
    )
    current_user.onboarding.update!(
      completed_at: Time.current,
      last_completed_step: 'paywall'
    )

    render json: { subscription: subscription }, status: :created
  end

  PRO_ENTITLEMENT_IDENTIFIER = 'Tiny Rest Pro'

  def create_pro_subscription
    return render json: { error: 'Unauthorized' }, status: :unauthorized unless current_user

    customer_info = normalize_hash(params['customerInfo'] || params[:customerInfo])
    active_rc_subscriptions = active_subscriptions_from_customer_info(customer_info)
    active_entitlement = active_pro_entitlement_from_customer_info(customer_info)

    if active_rc_subscriptions.empty? && active_entitlement.nil?
      return render json: { success: false, error: 'No active subscriptions found' }, status: :unprocessable_entity
    end

    # Prefer product subscription data; fall back to entitlement-only (e.g. RC Test Store).
    if active_rc_subscriptions.any?
      product_identifier, subscription_data_hash = active_rc_subscriptions.first
      created_from = product_identifier
      store = subscription_data_hash['store'] || subscription_data_hash[:store] || 'APP_STORE'
      price = normalize_hash(subscription_data_hash['price'] || subscription_data_hash[:price])
      amount = price['amount'] || price[:amount] || 0
      currency = (price['currency'] || price[:currency] || 'usd').to_s.downcase
      expires_date =
        subscription_data_hash['expiresDate'] ||
        subscription_data_hash[:expiresDate] ||
        subscription_data_hash['expirationDate'] ||
        subscription_data_hash[:expirationDate]
    else
      created_from = PRO_ENTITLEMENT_IDENTIFIER
      store = active_entitlement['store'] || active_entitlement[:store] || 'APP_STORE'
      amount = 0
      currency = 'usd'
      expires_date =
        active_entitlement['expirationDate'] ||
        active_entitlement[:expirationDate] ||
        active_entitlement['expiresDate'] ||
        active_entitlement[:expiresDate]
    end

    processor =
      case store.to_s.upcase
      when 'APP_STORE' then :apple
      when 'PLAY_STORE', 'GOOGLE_PLAY' then :google
      else :apple
      end

    expiration_date =
      expires_date.present? ? Time.parse(expires_date.to_s).to_date : nil

    subscription = current_user.subscriptions.create!(
      subscription_type: :pro,
      processor: processor,
      amount: amount,
      currency: currency,
      expiration_date: expiration_date,
      status: :active
    )

    current_user.onboarding&.update!(
      completed_at: Time.current,
      last_completed_step: 'paywall'
    )
    render json: {
      success: true,
      created_from: [created_from],
      subscriptions: [subscription]
    }, status: :created
  rescue ArgumentError => e
    Rails.logger.error("create_pro_subscription error: #{e.class} - #{e.message}")
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def normalize_hash(value)
    return {} if value.nil?
    return value.to_unsafe_h if value.is_a?(ActionController::Parameters)
    return value if value.is_a?(Hash)

    {}
  end

  def active_subscriptions_from_customer_info(customer_info)
    subscriptions_by_product_identifier = normalize_hash(
      customer_info['subscriptionsByProductIdentifier'] ||
      customer_info[:subscriptionsByProductIdentifier]
    )

    subscriptions_by_product_identifier.filter_map do |product_identifier, subscription_data|
      subscription_data_hash = normalize_hash(subscription_data)
      next unless active_flag?(subscription_data_hash['isActive'] || subscription_data_hash[:isActive])

      [product_identifier, subscription_data_hash]
    end
  end

  def active_pro_entitlement_from_customer_info(customer_info)
    entitlements = normalize_hash(customer_info['entitlements'] || customer_info[:entitlements])
    active = normalize_hash(entitlements['active'] || entitlements[:active])
    entitlement = active[PRO_ENTITLEMENT_IDENTIFIER] || active[PRO_ENTITLEMENT_IDENTIFIER.to_sym]
    return nil if entitlement.nil?

    normalize_hash(entitlement)
  end

  def active_flag?(value)
    value == true || value.to_s.downcase == 'true'
  end
end
