class RevenuecatService
  class << self
    # Validate a purchase and sync subscription status from RevenueCat
    # @param user [User] The user making the purchase
    # @param app_user_id [String] RevenueCat app user ID (typically user.id.to_s)
    # @param receipt_data [Hash] Optional receipt data from client (for Apple/Google receipts)
    # @return [Hash] Result with success status and subscription data
    def validate_purchase(user, app_user_id: nil, receipt_data: nil)
      app_user_id ||= user.id.to_s
      
      begin
        subscriber = Tarpon::Client.subscriber(app_user_id)
        
        # If receipt data is provided, post it to RevenueCat first
        if receipt_data.present?
          post_receipt_result = post_receipt(subscriber, receipt_data)
          unless post_receipt_result[:success]
            return post_receipt_result
          end
        end
        
        # Get subscriber info from RevenueCat
        subscriber_info = subscriber.get
        return error_response('Failed to fetch subscriber info') unless subscriber_info.success?
        
        subscriber_data = subscriber_info.body
        
        # Sync subscription based on RevenueCat data
        subscription = sync_subscription(user, subscriber_data, app_user_id)
        
        {
          success: true,
          subscription: subscription,
          subscriber: subscriber_data
        }
      rescue StandardError => e
        Rails.logger.error("RevenueCat validation error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        error_response("Validation failed: #{e.message}")
      end
    end

    # Post receipt to RevenueCat for validation
    # @param subscriber [Tarpon::Client::Subscriber] The subscriber client
    # @param receipt_data [Hash] Receipt data from client
    # @return [Hash] Result with success status
    def post_receipt(subscriber, receipt_data)
      # Determine store type from receipt data
      store = receipt_data[:store] || receipt_data['store'] || 'APP_STORE'
      receipt_token = receipt_data[:receipt] || receipt_data['receipt'] || receipt_data[:receipt_data] || receipt_data['receipt_data']
      
      return error_response('Missing receipt data') unless receipt_token
      
      begin
        case store.to_s.upcase
        when 'APP_STORE', 'IOS'
          result = subscriber.receipts.post_apple(receipt_token, is_restore: receipt_data[:is_restore] || false)
        when 'PLAY_STORE', 'GOOGLE_PLAY', 'ANDROID'
          result = subscriber.receipts.post_google(receipt_token, is_restore: receipt_data[:is_restore] || false)
        else
          return error_response("Unsupported store: #{store}")
        end
        
        if result.success?
          { success: true, data: result.body }
        else
          error_response("Failed to post receipt: #{result.body}")
        end
      rescue StandardError => e
        Rails.logger.error("Receipt posting error: #{e.message}")
        error_response("Failed to post receipt: #{e.message}")
      end
    end

    # Sync subscription status from RevenueCat subscriber data
    # @param user [User] The user
    # @param subscriber_data [Hash] RevenueCat subscriber data
    # @param app_user_id [String] RevenueCat app user ID
    # @return [Subscription] The synced subscription
    def sync_subscription(user, subscriber_data, app_user_id)
      entitlements = subscriber_data.dig('subscriber', 'entitlements') || {}
      subscriptions = subscriber_data.dig('subscriber', 'subscriptions') || {}
      
      # Find active entitlement or subscription
      active_entitlement = entitlements.values.find { |e| e['is_active'] == true }
      active_sub = subscriptions.values.find { |s| s['is_active'] == true }
      
      # Determine subscription status
      subscription_status = determine_subscription_status(active_entitlement, active_sub)
      
      # Get processor info
      processor, processor_id = extract_processor_info(active_sub, subscriber_data)
      
      # Get plan info
      plan = extract_plan_info(active_entitlement, active_sub)
      
      # Find or create subscription
      subscription = user.subscriptions.find_or_initialize_by(
        processor_id: processor_id || "rc_#{app_user_id}_#{SecureRandom.hex(8)}"
      )
      
      subscription.assign_attributes(
        processor: processor || :apple, # Default to apple if not specified
        subscription_type: "pro",
        amount: plan&.amount || 0,
        status: subscription_status,
        currency: plan&.currency || 'usd'
      )
      
      subscription.save!
      subscription
    end

    # Determine subscription status from RevenueCat data
    def determine_subscription_status(entitlement, subscription)
      return :active if entitlement&.dig('is_active') == true
      return :active if subscription&.dig('is_active') == true
      
      # Check expiration
      if subscription
        expires_at = subscription['expires_date']
        if expires_at && Time.parse(expires_at) < Time.current
          return :expired
        end
        
        # Check if cancelled
        if subscription['unsubscribe_detected_at']
          return :cancelled
        end
      end
      
      :expired
    end

    # Extract processor info from RevenueCat data
    def extract_processor_info(subscription, subscriber_data)
      return [:apple, nil] unless subscription
      
      store = subscription['store']
      original_transaction_id = subscription['original_transaction_id'] || 
                                subscription['original_purchase_date_ms']
      
      case store
      when 'APP_STORE', 'app_store'
        [:apple, original_transaction_id]
      when 'PLAY_STORE', 'play_store', 'GOOGLE_PLAY'
        [:google, original_transaction_id]
      else
        [:apple, original_transaction_id] # Default to apple
      end
    end

    # Extract plan info from RevenueCat data
    def extract_plan_info(entitlement, subscription)
      product_id = entitlement&.dig('product_identifier') || 
                   subscription&.dig('product_id')
      
      return nil unless product_id
      
      # Try to find plan by product ID
      Plan.find_by(apple_product_id: product_id) || 
      Plan.find_by(google_product_id: product_id)
    end

    # Get subscriber info from RevenueCat
    # @param app_user_id [String] RevenueCat app user ID
    # @return [Hash] Subscriber data
    def get_subscriber_info(app_user_id)
      subscriber = Tarpon::Client.subscriber(app_user_id)
      result = subscriber.get
      
      return nil unless result.success?
      result.body
    end

    # Identify a user with RevenueCat
    # @param app_user_id [String] RevenueCat app user ID
    # @param attributes [Hash] User attributes to set in RevenueCat
    def identify_user(app_user_id, attributes = {})
      subscriber = Tarpon::Client.subscriber(app_user_id)
      subscriber.identify(attributes)
    end

    # Grant promotional entitlement
    # @param app_user_id [String] RevenueCat app user ID
    # @param entitlement_id [String] Entitlement identifier
    def grant_promotional_entitlement(app_user_id, entitlement_id)
      subscriber = Tarpon::Client.subscriber(app_user_id)
      subscriber.entitlements.grant_promotional(entitlement_id)
    end

    private

    def error_response(message)
      {
        success: false,
        error: message
      }
    end
  end
end

