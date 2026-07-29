class Api::V1::PasswordsController < ApplicationController
  require 'sendgrid-ruby'
  include SendGrid

  skip_before_action :authenticate_user!

  # Request password reset - sends code to email
  def create
    email = params[:email].downcase
    
    unless email.present?
      return render json: { error: 'Email is required' }, status: :bad_request
    end

    user = User.find_by(email: email)

    if user
      # Generate 6-digit code
      code = generate_reset_code
      
      # Store code in reset_password_token (Devise field) and timestamp
      user.update(
        reset_password_token: code,
        reset_password_sent_at: Time.now
      )
      
      # Send email with code using SendGrid
      send_reset_code_email(user, code)
      
      render json: { 
        message: 'If an account with that email exists, you will receive a password reset code.' 
      }, status: :ok
    else
      # Don't reveal if email exists for security
      render json: { 
        message: 'If an account with that email exists, you will receive a password reset code.' 
      }, status: :ok
    end
  end

  # Verify the reset code
  def verify_code
    email = params[:email]
    code = params[:code]
    
    unless email.present? && code.present?
      return render json: { error: 'Email and code are required' }, status: :bad_request
    end

    user = User.find_by(email: email)
    
    unless user
      return render json: { error: 'Invalid email or code' }, status: :unauthorized
    end

    # Check if code matches and is not expired (1 hour)
    if user.reset_password_token == code && 
       user.reset_password_sent_at && 
       user.reset_password_sent_at > 1.hour.ago
      render json: { 
        message: 'Code verified successfully',
        reset_token: user.reset_password_token # Return token for password reset
      }, status: :ok
    else
      render json: { error: 'Invalid or expired code' }, status: :unauthorized
    end
  end

  # Reset password with verified code
  def update
    email = params[:email]
    code = params[:code] || params[:reset_token]
    password = params[:password]
    password_confirmation = params[:password_confirmation]
    
    unless email.present? && code.present?
      return render json: { error: 'Email and code are required' }, status: :bad_request
    end

    unless password.present?
      return render json: { error: 'Password is required' }, status: :bad_request
    end

    unless password == password_confirmation
      return render json: { error: 'Password confirmation does not match' }, status: :unprocessable_entity
    end

    user = User.find_by(email: email)
    
    unless user
      return render json: { error: 'Invalid email or code' }, status: :unauthorized
    end

    # Verify code again before resetting
    unless user.reset_password_token == code && 
           user.reset_password_sent_at && 
           user.reset_password_sent_at > 1.hour.ago
      return render json: { error: 'Invalid or expired code' }, status: :unauthorized
    end

    # Use Devise's password assignment
    user.password = password
    user.password_confirmation = password_confirmation
    
    if user.save
      # Clear the reset token
      user.update(reset_password_token: nil, reset_password_sent_at: nil)
      
      render json: { 
        message: 'Password has been reset successfully' 
      }, status: :ok
    else
      render json: { 
        errors: user.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  private

  def generate_reset_code
    # Generate a 6-digit code
    rand(100000..999999).to_s
  end

  def send_reset_code_email(user, code)
    # Validate SendGrid API key is present
    api_key = ENV.fetch('SENDGRID_API_KEY')
    # unless api_key.present?
    #   Rails.logger.error "SENDGRID_API_KEY environment variable is not set"
    #   raise "SendGrid API key is not configured. Please set SENDGRID_API_KEY environment variable."
    # end

    from = Email.new(email: ENV.fetch('SENDGRID_FROM_EMAIL', 'tinyrest.app.support@gmail.com'))
    to = Email.new(email: user.email)
    subject = 'Password Reset Code'
    
    # Generate email content
    html_content = generate_html_content(user, code)
    text_content = generate_text_content(user, code)
    
    # Create content objects for both HTML and plain text
    # SendGrid requires text/plain to be first, followed by text/html
    text_content_obj = Content.new(type: 'text/plain', value: text_content)
    html_content_obj = Content.new(type: 'text/html', value: html_content)
    
    # Create mail with plain text content first (SendGrid requirement)
    mail = Mail.new(from, subject, to, text_content_obj)
    
    # Add HTML content second
    mail.add_content(html_content_obj)

    sg = SendGrid::API.new(api_key: api_key)
    # sg.sendgrid_data_residency(region: 'eu')
    # uncomment the above line if you are sending mail using a regional EU subuser
    response = sg.client.mail._('send').post(request_body: mail.to_json)
    
    # Log response for debugging (remove in production if not needed)
    status_code = response.status_code.to_i
    Rails.logger.info "SendGrid Response: #{status_code}"
    Rails.logger.info "SendGrid Body: #{response.body}"
    
    # Check if email was successfully accepted (200, 201, 202 are all success codes)
    # 202 means accepted for delivery, which is success
    if [200, 201, 202].include?(status_code)
      Rails.logger.info "Email sent successfully via SendGrid"
    else
      error_message = "Failed to send email via SendGrid"
      if response.body.present?
        parsed_body = JSON.parse(response.body) rescue response.body
        error_message += ": #{parsed_body}"
      end
      Rails.logger.error "SendGrid Error (#{status_code}): #{error_message}"
      
      # Provide helpful error message for common issues
      if status_code == 401
        raise "SendGrid authentication failed. Please verify your SENDGRID_API_KEY is correct and has proper permissions."
      else
        raise error_message
      end
    end
  end

  def generate_html_content(user, code)
    <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <meta content='text/html; charset=UTF-8' http-equiv='Content-Type' />
        </head>
        <body>
          <h1>Password Reset Code</h1>
          <p>Hello #{user.email},</p>
          <p>You have requested to reset your password. Use the following code to reset your password:</p>
          <h2 style="font-size: 32px; letter-spacing: 5px; text-align: center; padding: 20px; background-color: #f0f0f0; border-radius: 5px; display: inline-block;">
            #{code}
          </h2>
          <p>This code will expire in 1 hour.</p>
          <p>If you didn't request this, please ignore this email.</p>
        </body>
      </html>
    HTML
  end

  def generate_text_content(user, code)
    <<~TEXT
      Password Reset Code

      Hello #{user.email},

      You have requested to reset your password. Use the following code to reset your password:

      #{code}

      This code will expire in 1 hour.

      If you didn't request this, please ignore this email.
    TEXT
  end
end

