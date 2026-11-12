# frozen_string_literal: true

require "securerandom"

namespace :support do
  desc "Point the Support (admin inbox) account at EMAIL with a new password, keeping its conversations. " \
       "Usage: EMAIL=you@example.com [PASSWORD=...] bin/rails support:set_account"
  task set_account: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Set EMAIL. Example: EMAIL=you@example.com bin/rails support:set_account" if email.blank?

    password = ENV["PASSWORD"].presence
    generated = password.nil?
    password ||= SecureRandom.base58(20)

    conflict = User.find_by(email: email)
    user = User.support_account

    if conflict && user && conflict.id != user.id
      abort "#{email} already belongs to another user (id #{conflict.id}). Nothing changed."
    end

    user ||= conflict || User.new
    previous_email = user.email
    action = user.new_record? ? "Created" : "Updated"

    user.assign_attributes(
      email: email,
      password: password,
      password_confirmation: password,
      username: User::SUPPORT_USERNAME,
      first_name: user.first_name.presence || "Support",
      last_name: user.last_name.presence || "Team"
    )

    abort "Could not save: #{user.errors.full_messages.to_sentence}" unless user.save

    puts "#{action} Support account (id #{user.id})"
    puts "Email: #{previous_email} -> #{user.email}" if previous_email.present? && previous_email != user.email
    puts "Email: #{user.email}" if previous_email.blank? || previous_email == user.email
    puts(generated ? "Password (generated, shown once): #{password}" : "Password: as given in PASSWORD")
    puts "Admin login works now, since the account keeps the username '#{User::SUPPORT_USERNAME}'."
  end
end
