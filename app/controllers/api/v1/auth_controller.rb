class Api::V1::AuthController < ApplicationController
  include Devise::Controllers::Helpers
  require 'sendgrid-ruby'
  include SendGrid

  # Skip authentication for public actions
  skip_before_action :authenticate_user!, only: [
    :login,
    :signup,
    :logout,
    :verify_signup,
    :resend_signup_code
  ]

  def login
    user = User.find_for_authentication(email: params[:email])
    if user&.deleted_at.present?
      render json: { error: 'Invalid credentials' }, status: :unauthorized
    elsif user&.valid_password?(params[:password])
      if email_verification_required? && user.email_verified_at.blank?
        issue_verification_code!(user)
        return render json: {
          error: 'Please verify your email before logging in.'
        }, status: :unauthorized
      end

      token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
      render json: { token: token, user: user_auth_payload(user) }, status: :ok
    else
      render json: { error: 'Invalid credentials' }, status: :unauthorized
    end
  end

  def signup
    email = params[:email].to_s.downcase.strip
    password = params[:password]
    password_confirmation = params[:password_confirmation]

    unless password_confirmation.present?
      return render json: {
        message: 'Validation failed',
        errors: ["Password confirmation can't be blank"]
      }, status: :unprocessable_entity
    end

    existing = User.find_by(email: email)
    if existing
      if existing.email_verified_at.present?
        return render json: {
          message: 'Validation failed',
          errors: ['Email has already been taken']
        }, status: :unprocessable_entity
      end

      existing.password = password
      existing.password_confirmation = password_confirmation
      if existing.save
        return render_signup_success(existing)
      else
        return render json: {
          message: 'Validation failed',
          errors: existing.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    user = User.new(
      email: email,
      password: password,
      password_confirmation: password_confirmation
    )
    if user.save
      render_signup_success(user)
    else
      render json: {
        message: 'Validation failed',
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def verify_signup
    email = params[:email].to_s.downcase.strip
    code = params[:code].to_s.strip

    unless email.present? && code.present?
      return render json: { error: 'Email and code are required' }, status: :bad_request
    end

    user = User.find_by(email: email)
    unless user
      return render json: { error: 'Invalid or expired code' }, status: :unauthorized
    end

    if user.email_verified_at.present?
      token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
      return render json: { token: token, user: user_auth_payload(user) }, status: :ok
    end

    unless verification_code_valid?(user, code)
      return render json: { error: 'Invalid or expired code' }, status: :unauthorized
    end

    user.update!(
      email_verified_at: Time.current,
      email_verification_code: nil,
      email_verification_sent_at: nil
    )

    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    render json: { token: token, user: user_auth_payload(user) }, status: :ok
  end

  def resend_signup_code
    email = params[:email].to_s.downcase.strip

    unless email.present?
      return render json: { error: 'Email is required' }, status: :bad_request
    end

    user = User.find_by(email: email)
    if user && user.email_verified_at.blank?
      issue_verification_code!(user)
    end

    render json: {
      message: 'If an unverified account with that email exists, you will receive a verification code.'
    }, status: :ok
  end

  def logout
    token = request.headers['Authorization']&.split&.last
    if token
      begin
        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        # Add token to denylist if it has a jti
        if payload['jti']
          JwtDenylist.create(jti: payload['jti'], exp: payload['exp'] ? Time.at(payload['exp']) : Time.now + 1.hour)
        end
        render json: { message: 'Logged out successfully' }, status: :ok
      rescue JWT::ExpiredSignature => e
        # Handle expired tokens gracefully - decode without verification to get jti
        begin
          require 'jwt'
          # Decode without verification to extract payload from expired token
          decoded = JWT.decode(token, nil, false)[0]
          if decoded['jti']
            JwtDenylist.create(jti: decoded['jti'], exp: decoded['exp'] ? Time.at(decoded['exp']) : Time.now + 1.hour)
          end
          render json: { message: 'Token expired, but logged out successfully' }, status: :ok
        rescue => decode_error
          # If we can't decode it at all, just return success (token is already invalid)
          render json: { message: 'Token expired' }, status: :ok
        end
      rescue JWT::DecodeError => e
        render json: { error: "Invalid token: #{e.message}" }, status: :bad_request
      rescue StandardError => e
        render json: { error: "Failed to revoke token: #{e.message}" }, status: :unprocessable_entity
      end
    else
      render json: { error: 'No token provided' }, status: :bad_request
    end
  end

  def refresh_user
    token = Warden::JWTAuth::UserEncoder.new.call(current_user, :user, nil).first
    render json: { token:, user: user_auth_payload(current_user)}, status: :ok
  end

  private

  def user_auth_payload(user)
    {
      id: user.id,
      email: user.email,
      onboarding_completed: user.onboarding&.completed_at.present?,
      subscription_type: user.subscription_type_for_payload
    }
  end

  def verification_pending_payload(user)
    {
      message: 'Verification code sent',
      email: user.email,
      needs_verification: true
    }
  end

  # Production: email code confirmation.
  # Development + test: auto-verify and return JWT so local/dev stays offline.
  def render_signup_success(user)
    if email_verification_required?
      issue_verification_code!(user)
      render json: verification_pending_payload(user), status: :created
    else
      user.update!(
        email_verified_at: Time.current,
        email_verification_code: nil,
        email_verification_sent_at: nil
      )
      token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
      render json: { token: token, user: user_auth_payload(user) }, status: :created
    end
  end

  def email_verification_required?
    Rails.env.production?
  end

  def generate_verification_code
    rand(100000..999999).to_s
  end

  def verification_code_valid?(user, code)
    user.email_verification_code == code &&
      user.email_verification_sent_at.present? &&
      user.email_verification_sent_at > 1.hour.ago
  end

  def issue_verification_code!(user)
    code = generate_verification_code
    user.update!(
      email_verification_code: code,
      email_verification_sent_at: Time.current
    )
    send_verification_code_email(user, code)
  end

  def send_verification_code_email(user, code)
    if Rails.env.test?
      Rails.logger.info(
        "Skipping signup verification email in test " \
        "(email=#{user.email}, code=#{code})"
      )
      return
    end

    api_key = ENV['SENDGRID_API_KEY']

    unless api_key.present?
      Rails.logger.warn 'SENDGRID_API_KEY missing; skipping signup verification email'
      return
    end

    from = Email.new(email: ENV.fetch('SENDGRID_FROM_EMAIL', 'tinyrest.app.support@gmail.com'))
    to = Email.new(email: user.email)
    subject = 'Verify your TinyRest account'

    html_content = generate_verification_html_content(user, code)
    text_content = generate_verification_text_content(user, code)

    text_content_obj = Content.new(type: 'text/plain', value: text_content)
    html_content_obj = Content.new(type: 'text/html', value: html_content)

    mail = Mail.new(from, subject, to, text_content_obj)
    mail.add_content(html_content_obj)

    sg = SendGrid::API.new(api_key: api_key)
    response = sg.client.mail._('send').post(request_body: mail.to_json)

    status_code = response.status_code.to_i
    Rails.logger.info "SendGrid Response: #{status_code}"
    Rails.logger.info "SendGrid Body: #{response.body}"

    if [200, 201, 202].include?(status_code)
      Rails.logger.info 'Verification email sent successfully via SendGrid'
    else
      error_message = 'Failed to send email via SendGrid'
      if response.body.present?
        parsed_body = JSON.parse(response.body) rescue response.body
        error_message += ": #{parsed_body}"
      end
      Rails.logger.error "SendGrid Error (#{status_code}): #{error_message}"

      if status_code == 401
        raise 'SendGrid authentication failed. Please verify your SENDGRID_API_KEY is correct and has proper permissions.'
      else
        raise error_message
      end
    end
  end

  def generate_verification_html_content(user, code)
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta content='text/html; charset=UTF-8' http-equiv='Content-Type' />
        </head>
        <body>
          <h1>Verify your email</h1>
          <p>Hello #{user.email},</p>
          <p>Use the following code to finish creating your TinyRest account:</p>
          <h2 style="font-size: 32px; letter-spacing: 5px; text-align: center; padding: 20px; background-color: #f0f0f0; border-radius: 5px; display: inline-block;">
            #{code}
          </h2>
          <p>This code will expire in 1 hour.</p>
          <p>If you didn't create an account, please ignore this email.</p>
        </body>
      </html>
    HTML
  end

  def generate_verification_text_content(user, code)
    <<~TEXT
      Verify your email

      Hello #{user.email},

      Use the following code to finish creating your TinyRest account:

      #{code}

      This code will expire in 1 hour.

      If you didn't create an account, please ignore this email.
    TEXT
  end
end
