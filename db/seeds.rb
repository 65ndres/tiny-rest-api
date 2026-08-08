# Create support user (admin inbox login)
support_password = ENV.fetch('SUPPORT_USER_PASSWORD', 'asdfasdfasdf')
support_user = User.find_or_initialize_by(email: User::SUPPORT_EMAIL)
support_user.assign_attributes(
  password: support_password,
  password_confirmation: support_password,
  username: User::SUPPORT_USERNAME,
  first_name: 'Support',
  last_name: 'Team'
)
support_user.save!

# Create default trial plan
Plan.default_trial_plan

# Create Basic plan
Plan.find_or_create_by!(name: 'Basic') do |plan|
  plan.amount = 0
  plan.currency = 'usd'
  plan.interval = 'month'
end

20.times do
  User.create!(
    email: Faker::Internet.email,
    password: Faker::Internet.password,
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name
  )
end
