require "test_helper"

class Api::V1::AuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    @valid_email = "test@example.com"
    @valid_password = "password123"
  end

  def create_verified_user(email: @valid_email, password: @valid_password)
    User.create!(
      email: email,
      password: password,
      password_confirmation: password,
      email_verified_at: Time.current
    )
  end

  # Login Tests
  test "should login with valid credentials" do
    user = create_verified_user

    post "/api/v1/auth/login", params: {
      email: @valid_email,
      password: @valid_password
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["token"].present?
    assert_equal user.id, json_response["user"]["id"]
    assert_equal user.email, json_response["user"]["email"]
  end

  test "should not login with invalid email" do
    post "/api/v1/auth/login", params: {
      email: "nonexistent@example.com",
      password: @valid_password
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid credentials", json_response["error"]
  end

  test "should not login with invalid password" do
    create_verified_user

    post "/api/v1/auth/login", params: {
      email: @valid_email,
      password: "wrong_password"
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid credentials", json_response["error"]
  end

  test "should not login without email" do
    post "/api/v1/auth/login", params: {
      password: @valid_password
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid credentials", json_response["error"]
  end

  test "should not login without password" do
    post "/api/v1/auth/login", params: {
      email: @valid_email
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid credentials", json_response["error"]
  end

  test "should not login when email is unverified" do
    User.create!(
      email: @valid_email,
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "123456",
      email_verification_sent_at: Time.current
    )

    post "/api/v1/auth/login", params: {
      email: @valid_email,
      password: @valid_password
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Please verify your email before logging in.", json_response["error"]
  end

  # Signup Tests
  test "should signup with valid credentials and auto-verify in test" do
    assert_difference "User.count", 1 do
      post "/api/v1/auth/signup", params: {
        email: "newuser@example.com",
        password: @valid_password,
        password_confirmation: @valid_password
      }
    end

    assert_response :created
    json_response = JSON.parse(response.body)
    assert json_response["token"].present?
    assert_equal "newuser@example.com", json_response["user"]["email"]
    assert_nil json_response["needs_verification"]

    user = User.find_by(email: "newuser@example.com")
    assert user.email_verified_at.present?
    assert_nil user.email_verification_code
  end

  test "should signup with valid credentials and require verification in development" do
    previous_env = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(
      :@_env,
      ActiveSupport::EnvironmentInquirer.new("development")
    )

    begin
      assert_difference "User.count", 1 do
        post "/api/v1/auth/signup", params: {
          email: "devuser@example.com",
          password: @valid_password,
          password_confirmation: @valid_password
        }
      end

      assert_response :created
      json_response = JSON.parse(response.body)
      assert_nil json_response["token"]
      assert_equal true, json_response["needs_verification"]
      assert_equal "devuser@example.com", json_response["email"]

      user = User.find_by(email: "devuser@example.com")
      assert user.email_verified_at.blank?
      assert user.email_verification_code.present?
      assert_equal 6, user.email_verification_code.length
    ensure
      Rails.instance_variable_set(:@_env, previous_env)
    end
  end

  test "should signup with valid credentials and require verification in production" do
    previous_env = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(
      :@_env,
      ActiveSupport::EnvironmentInquirer.new("production")
    )

    begin
      assert_difference "User.count", 1 do
        post "/api/v1/auth/signup", params: {
          email: "produser@example.com",
          password: @valid_password,
          password_confirmation: @valid_password
        }
      end

      assert_response :created
      json_response = JSON.parse(response.body)
      assert_nil json_response["token"]
      assert_equal true, json_response["needs_verification"]
      assert_equal "produser@example.com", json_response["email"]

      user = User.find_by(email: "produser@example.com")
      assert user.email_verified_at.blank?
      assert user.email_verification_code.present?
      assert_equal 6, user.email_verification_code.length
    ensure
      Rails.instance_variable_set(:@_env, previous_env)
    end
  end

  test "should not signup with invalid email" do
    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: "invalid_email",
        password: @valid_password,
        password_confirmation: @valid_password
      }
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not signup with duplicate verified email" do
    create_verified_user

    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: @valid_email,
        password: @valid_password,
        password_confirmation: @valid_password
      }
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should auto-verify unverified email on signup in test" do
    user = User.create!(
      email: @valid_email,
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "111111",
      email_verification_sent_at: 10.minutes.ago
    )

    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: @valid_email,
        password: @valid_password,
        password_confirmation: @valid_password
      }
    end

    assert_response :created
    json_response = JSON.parse(response.body)
    assert json_response["token"].present?

    user.reload
    assert user.email_verified_at.present?
    assert_nil user.email_verification_code
  end

  test "should not signup with password mismatch" do
    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: "newuser@example.com",
        password: @valid_password,
        password_confirmation: "different_password"
      }
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not signup with short password" do
    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: "newuser@example.com",
        password: "short",
        password_confirmation: "short"
      }
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not signup without password confirmation" do
    assert_no_difference "User.count" do
      post "/api/v1/auth/signup", params: {
        email: "newuser@example.com",
        password: @valid_password
      }
    end

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  # Signup verification Tests
  test "should verify signup code and return token" do
    user = User.create!(
      email: "newuser@example.com",
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "654321",
      email_verification_sent_at: Time.current
    )

    post "/api/v1/auth/signup/verify", params: {
      email: "newuser@example.com",
      code: "654321"
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["token"].present?
    assert_equal user.id, json_response["user"]["id"]

    user.reload
    assert user.email_verified_at.present?
    assert_nil user.email_verification_code
  end

  test "should not verify with invalid code" do
    User.create!(
      email: "newuser@example.com",
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "654321",
      email_verification_sent_at: Time.current
    )

    post "/api/v1/auth/signup/verify", params: {
      email: "newuser@example.com",
      code: "000000"
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid or expired code", json_response["error"]
  end

  test "should not verify with expired code" do
    User.create!(
      email: "newuser@example.com",
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "654321",
      email_verification_sent_at: 2.hours.ago
    )

    post "/api/v1/auth/signup/verify", params: {
      email: "newuser@example.com",
      code: "654321"
    }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Invalid or expired code", json_response["error"]
  end

  test "should resend signup verification code" do
    user = User.create!(
      email: "newuser@example.com",
      password: @valid_password,
      password_confirmation: @valid_password,
      email_verification_code: "111111",
      email_verification_sent_at: 10.minutes.ago
    )

    post "/api/v1/auth/signup/resend", params: {
      email: "newuser@example.com"
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["message"].present?

    user.reload
    assert_not_equal "111111", user.email_verification_code
  end

  # Logout Tests
  test "should logout with valid token" do
    create_verified_user

    # Get a token by logging in first
    post "/api/v1/auth/login", params: {
      email: @valid_email,
      password: @valid_password
    }
    login_response = JSON.parse(response.body)
    token = login_response["token"]

    # Now logout
    delete "/api/v1/auth/logout", headers: {
      "Authorization" => "Bearer #{token}"
    }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Logged out successfully", json_response["message"]

    # Verify token is in denylist
    payload = Warden::JWTAuth::TokenDecoder.new.call(token)
    assert JwtDenylist.exists?(jti: payload["jti"])
  end

  test "should not logout without token" do
    delete "/api/v1/auth/logout"

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "No token provided", json_response["error"]
  end

  test "should not logout with invalid token" do
    delete "/api/v1/auth/logout", headers: {
      "Authorization" => "Bearer invalid_token_here"
    }

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert json_response["error"].present?
    assert json_response["error"].include?("Invalid token")
  end

  test "should logout with expired token" do
    user = create_verified_user

    # Create an expired token manually using the same secret as devise-jwt
    expired_payload = {
      sub: user.id,
      jti: SecureRandom.uuid,
      exp: 1.hour.ago.to_i,
      iat: 2.hours.ago.to_i
    }

    require 'jwt'
    # Use the same secret key that devise-jwt uses
    secret = ENV['DEVISE_JWT_SECRET_KEY'].presence || Rails.application.secret_key_base
    expired_token = JWT.encode(expired_payload, secret, 'HS256')

    delete "/api/v1/auth/logout", headers: {
      "Authorization" => "Bearer #{expired_token}"
    }

    # The controller should handle expired tokens gracefully
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["message"].present?
    # Should either be "Token expired, but logged out successfully" or "Token expired"
    assert json_response["message"].include?("expired") || json_response["message"].include?("successfully")
  end

  test "should logout with malformed authorization header" do
    delete "/api/v1/auth/logout", headers: {
      "Authorization" => "InvalidFormat"
    }

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert json_response["error"].present?
  end
end
