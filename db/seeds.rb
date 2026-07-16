# Create support user
support_user = User.find_or_create_by!(email: 'support@promesas.com') do |user|
  user.password = 'asdfasdfasdf'
  user.username = 'Support'
  user.first_name = 'Support'
  user.last_name = 'Team'
end

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
