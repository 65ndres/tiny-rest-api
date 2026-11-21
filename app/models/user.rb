class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  SUPPORT_EMAIL = "tinyrest.app.support@gmail.com"
  SUPPORT_USERNAME = "Support"
  WELCOME_MESSAGE_BODY =
    "Welcome to TinyRest! We're glad you're here. If you have any questions " \
    "or need help with naps, feeding, or your account, reply here anytime — " \
    "we're happy to help."

  # Baby profile columns moved to babies (see CreateBabies). Kept in the table
  # until a follow-up migration drops them.
  self.ignored_columns += %w[
    baby_name baby_birthdate daily_nap_count daily_nap_count_alt
    day_start_minutes day_end_minutes
  ]

  # Legacy user-level baby attributes, now read from and written to the
  # account's first baby. Lets onboarding, admin tools and seeds keep using
  # `user.baby_birthdate` etc. API requests use the selected baby instead.
  BABY_ATTRIBUTE_MAP = {
    baby_name: :name,
    baby_birthdate: :birthdate,
    daily_nap_count: :daily_nap_count,
    daily_nap_count_alt: :daily_nap_count_alt,
    day_start_minutes: :day_start_minutes,
    day_end_minutes: :day_end_minutes
  }.freeze

  devise :database_authenticatable, :registerable, :recoverable, :validatable, :jwt_authenticatable, jwt_revocation_strategy: self

  # Messaging associations
  has_many :user_conversations, dependent: :destroy
  has_many :conversations, through: :user_conversations
  has_many :sent_messages, class_name: "Message", foreign_key: "sender_id", dependent: :destroy
  has_many :received_messages, class_name: "Message", foreign_key: "receiver_id", dependent: :destroy
  has_many :admin_conversations, dependent: :destroy

  # Subscription associations
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: "Subscription"

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
  has_many :babies, -> { order(:created_at, :id) },
           dependent: :destroy, inverse_of: :user, autosave: false, validate: false

  BABY_ATTRIBUTE_MAP.each do |user_attribute, baby_attribute|
    define_method(user_attribute) { primary_baby.public_send(baby_attribute) }
    define_method("#{user_attribute}=") { |value| primary_baby.public_send("#{baby_attribute}=", value) }
  end

  # The account's first baby (the one existing data was migrated into).
  def primary_baby
    babies.to_a.first || babies.build
  end

  # Baby for an API request: the one named by the client, else the first.
  def find_baby(id)
    (id.present? && babies.find_by(id: id)) || primary_baby
  end

  DEFAULT_DAY_START_MINUTES = 570  # 9:30 AM
  DEFAULT_DAY_END_MINUTES = 1320   # 10:00 PM
  ALLOWED_NAP_COUNT_RANGES = [ [ 0, 1 ], [ 1, 2 ], [ 2, 3 ], [ 3, 4 ], [ 4, 5 ], [ 5, 6 ] ].freeze

  validates :username, presence: true, uniqueness: true, allow_nil: true
  validates :time_zone, presence: true
  validate :time_zone_must_be_valid
  validate :primary_baby_must_be_valid

  # Search users by username
  scope :search_by_username, ->(query) { where("username ILIKE ?", "%#{query}%") }

  def self.support_account
    find_by(email: SUPPORT_EMAIL) || find_by(username: SUPPORT_USERNAME)
  end

  def support_account?
    email == SUPPORT_EMAIL || username == SUPPORT_USERNAME
  end

  after_save :persist_primary_baby
  after_create :generate_username
  after_create :send_welcome_message
  after_create :setup_onboarding
  # after_create :create_free_trial_subscription

  def generate_username
    return unless email.present?
    return if username.present? # Skip if username is already set

    # Extract email username (part before @)
    email_username = email.split("@").first

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

  def primary_baby_must_be_valid
    baby = babies.to_a.first
    return unless baby && (baby.new_record? || baby.changed?)
    return if baby.valid?

    baby.errors.each do |error|
      errors.add(BABY_ATTRIBUTE_MAP.key(error.attribute) || :base, error.message)
    end
  end

  def persist_primary_baby
    baby = babies.to_a.first
    if baby.nil?
      babies.create!
    elsif baby.new_record? || baby.changed?
      # Built before this user had an id; point it at the saved row.
      baby.user = self
      baby.save!
    end
  end

  def time_zone_must_be_valid
    return if time_zone.blank?

    TZInfo::Timezone.get(time_zone)
  rescue TZInfo::InvalidTimezoneIdentifier
    errors.add(:time_zone, "is not valid")
  end

  def create_free_trial_subscription
    basic_plan = Plan.find_by(name: "Basic")
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
