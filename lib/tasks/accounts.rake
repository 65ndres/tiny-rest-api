# frozen_string_literal: true

namespace :accounts do
  desc "Create a login-ready Pro account. Usage: NAPS=3 TAKEN=1 [AGE=months] bin/rails accounts:create"
  task create: :environment do
    if ENV["NAPS"].blank?
      abort "Set NAPS and TAKEN, and optionally AGE in months. Example: NAPS=3 TAKEN=1 AGE=6 bin/rails accounts:create"
    end

    result = PreparedAccountCreator.call(
      daily_nap_count: ENV["NAPS"],
      naps_taken: ENV.fetch("TAKEN", 0),
      baby_age_months: ENV["AGE"]
    )

    puts "Email: #{result.email}"
    puts "Password: #{result.password}"
    puts "Baby age: #{result.baby_age_months} months"
    puts "Naps per day: #{result.daily_nap_count}"
    puts "Naps already taken today: #{result.naps_taken}"
    puts "Plan: pro"
    puts "Onboarding: complete"
  rescue PreparedAccountCreator::Error => e
    abort e.message
  end
end
