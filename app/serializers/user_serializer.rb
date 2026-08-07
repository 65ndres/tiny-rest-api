class UserSerializer
  include JSONAPI::Serializer
  attributes :id, :email, :first_name, :last_name, :onboarding_completed, :subscription_type

  def onboarding_completed
    object.onboarding&.completed_at.present?
  end

  def subscription_type
    object.current_subscription&.subscription_type
  end
end
