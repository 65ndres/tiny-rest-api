class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers

  before_action :authenticate_user!, unless: :public_endpoint?

  def authenticate_user!
    return if authorized?

    head :unauthorized
  end

  def authorized?
    token = request.headers['Authorization']&.split&.last
    return false unless token

    begin
      payload = Warden::JWTAuth::TokenDecoder.new.call(token)
      # Check if token is expired
      return false unless payload['exp'] && Time.at(payload['exp']) > Time.now

      if payload['jti'] && JwtDenylist.exists?(jti: payload['jti'])
        return false
      end

      true
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      false
    end
  end

  def current_user
    @current_user ||= begin
      token = request.headers['Authorization']&.split&.last
      return nil unless token

      begin
        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        unless authorized?
          nil
        else
          user = User.find(payload['sub'])
          user.deleted_at.present? ? nil : user
        end
      rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
        nil
      end
    end
  end

  def public_endpoint?
    # Allow specific routes to be public

    request.path.match?(%r{^/api/v1/auth/(login|signup|password)$})
  end
end