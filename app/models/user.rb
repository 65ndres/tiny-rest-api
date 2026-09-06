class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  SUPPORT_EMAIL = 'support.tinyrest.app@gmail.com'
  SUPPORT_USERNAME = 'Support'
  WELCOME_MESSAGE_BODY =
    "Welcome to TinyRest! We're glad you're here. If you have any questions " \
    "or need help with naps, feeding, or your account, reply here anytime — " \
    "we're happy to help."

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

  DEFAULT_DAY_START_MINUTES = 570  # 9:30 AM
  DEFAULT_DAY_END_MINUTES = 1320   # 10:00 PM
  ALLOWED_NAP_COUNT_RANGES = [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]].freeze

  validates :username, presence: true, uniqueness: true, allow_nil: true
  validates :daily_nap_count, inclusion: { in: 0..6 }
  validates :daily_nap_count_alt, inclusion: { in: 0..6 }, allow_nil: true
  validates :day_start_minutes, :day_end_minutes,
            presence: true,
            inclusion: { in: 0..1439 }
  validate :baby_birthdate_must_be_valid, if: -> { baby_birthdate.present? }
  validate :day_window_must_be_ordered
  validate :daily_nap_count_alt_must_be_allowed_range

  # Search users by username
  scope :search_by_username, ->(query) { where('username ILIKE ?', "%#{query}%") }

  def self.support_account
    find_by(email: SUPPORT_EMAIL) || find_by(username: SUPPORT_USERNAME)
  end

  def support_account?
    email == SUPPORT_EMAIL || username == SUPPORT_USERNAME
  end

  after_create :generate_username
  after_create :send_welcome_message
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
    return if support_account?

    support_user = User.support_account
    unless support_user
      Rails.logger.warn("Support user missing; skipping welcome message for user #{id}")
      return
    end

    conversation = Conversation.find_or_create_support_for!(self)
    return if conversation.messages.exists?

    conversation.messages.create!(
      body: WELCOME_MESSAGE_BODY,
      sender: support_user
    )
  rescue StandardError => e
    Rails.logger.error("Failed to send welcome message for user #{id}: #{e.message}")
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
    elsif baby_birthdate < 5.years.ago.to_date
      errors.add(:baby_birthdate, 'must be within the last 5 years')
    end
  end

  def day_window_must_be_ordered
    return if day_start_minutes.blank? || day_end_minutes.blank?
    return if day_start_minutes < day_end_minutes

    errors.add(:day_end_minutes, 'must be after day start')
  end

  def daily_nap_count_alt_must_be_allowed_range
    return if daily_nap_count_alt.nil?

    unless ALLOWED_NAP_COUNT_RANGES.include?([daily_nap_count, daily_nap_count_alt])
      errors.add(:daily_nap_count_alt, 'must be an allowed nap range')
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