class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable, :recoverable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  # Messaging associations
  has_many :user_conversations, dependent: :destroy
  has_many :conversations, through: :user_conversations
  has_many :sent_messages, class_name: 'Message', foreign_key: 'sender_id', dependent: :destroy
  has_many :received_messages, class_name: 'Message', foreign_key: 'receiver_id', dependent: :destroy
  has_many :admin_conversations, dependent: :destroy

  # Subscription associations
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: 'Subscription'

  def latest_subscription
    subscriptions.order(created_at: :desc).first
  end

  # Block account deletion only while there is an active subscription.
  def cannot_delete_account_due_to_subscription?
    current_subscription.present?
  end

  # Onboarding
  has_one :onboarding, dependent: :destroy

  has_many :timer_runs, dependent: :destroy

  validates :username, presence: true, uniqueness: true, allow_nil: true
  validates :daily_nap_count, inclusion: { in: 1..5 }
  validate :baby_birthdate_must_be_valid, if: -> { baby_birthdate.present? }

  # Search users by username
  scope :search_by_username, ->(query) { where('username ILIKE ?', "%#{query}%") }

  after_create :generate_username
  # after_create :send_welcome_message
  after_create :setup_onboarding
  # after_create :create_free_trial_subscription
  
  def generate_username
    return unless email.present?
    return if username.present? # Skip if username is already set
    
    # Extract email username (part before @)
    email_username = email.split('@').first
    
    # List of random words to append
    random_words = %w[
      star moon sun ocean river mountain forest valley desert island
      cloud rainbow thunder lightning storm breeze wave tide shore
      eagle hawk dove sparrow robin owl falcon swan peacock
      rose lily tulip daisy sunflower orchid jasmine lavender
      peace hope faith love joy grace wisdom courage strength
      warrior guardian protector seeker wanderer explorer dreamer
      light shadow dawn dusk twilight sunrise sunset horizon
    ]
    
    # Generate username with email and random word, ensuring uniqueness
    while true
      random_word = random_words.sample
      self.username = "#{email_username}_#{random_word}"
      
      # Check if username is valid (unique)
      errors.clear
      if self.valid?
        break
      end
      
      # If not unique, try with a random number appended
      errors.clear
      self.username = "#{email_username}_#{random_word}_#{rand(1000..9999)}"
      break if self.valid?
    end
    
    save
  end

  def send_welcome_message
    return if self.username == "Support"
    conversation = Conversation.new(name: "Support", conversation_type: 1)
    support_user = User.find_by(username: "Support")
    conversation.users << self
    conversation.users << support_user
    conversation.save!

    welcome_message = "Welcome to Promesas! We're so glad you're here. We hope you find peace, inspiration, and strength through God's word. If you have any questions or need support, feel free to reach out to us anytime. Blessings!"
    
    conversation.messages.create(
      body: welcome_message,
      sender_id: support_user.id
    )
    # conversation.save!
  end

  def setup_onboarding
    create_onboarding!
  end


  def subscription_type
    current_subscription&.subscription_type
  end

  # def create_admin_conversation
  #   admin_conversation = AdminConversation.create!(name: "Support")
  #   admin_conversation.users << self
  #   admin_conversation.save!
  # end

  def subscription_status
    current_subscription&.subscription_type
  end

  # Custom JWT claims – included in the token on login/signup
  def jwt_payload
    onboarding_record = onboarding
    {
      onboarding_completed: onboarding_record&.completed_at.present?,
      subscription_type: subscription_type_for_payload
    }
  end

  # Used for JWT claims and API payloads that need to include subscription info.
  # Returns `nil` when the user has no active subscription.
  # Queries fresh to avoid a stale has_one cache after creates in the same request.
  def subscription_type_for_payload
    current_subscription&.subscription_type
  end

  def current_subscription
    subscriptions.active_subscriptions.order(created_at: :desc).first
  end

  def baby_birthdate_must_be_valid
    if baby_birthdate > Date.current
      errors.add(:baby_birthdate, 'must be in the past')
    elsif baby_birthdate < 4.years.ago.to_date
      errors.add(:baby_birthdate, 'must be within the last 4 years')
    end
  end

  def create_free_trial_subscription
    basic_plan = Plan.find_by(name: 'Basic')
    return unless basic_plan

    subscriptions.create!(
      subscription_type: :free_trial,
      processor: :apple, # IAP processor
      processor_id: "free_trial_#{id}_#{SecureRandom.hex(8)}",
      amount: 199.0,
      currency: basic_plan.currency
    )
  end
end