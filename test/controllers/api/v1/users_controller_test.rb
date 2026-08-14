require "test_helper"

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user1 = User.create!(
      email: "user1@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "user1",
      first_name: "John",
      last_name: "Doe"
    )
    @user2 = User.create!(
      email: "user2@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "user2",
      first_name: "Jane",
      last_name: "Smith"
    )
    @user3 = User.create!(
      email: "user3@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "johndoe123"
    )

    @token1 = Warden::JWTAuth::UserEncoder.new.call(@user1, :user, nil).first
    @token2 = Warden::JWTAuth::UserEncoder.new.call(@user2, :user, nil).first
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token}" }
  end

  test "should show current user profile" do
    get "/api/v1/user", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal @user1.first_name, json_response["first_name"]
    assert_equal @user1.last_name, json_response["last_name"]
    assert_equal @user1.email, json_response["email"]
    assert_equal @user1.username, json_response["username"]
  end

  test "should not show user profile without authentication" do
    get "/api/v1/user"

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Unauthorized", json_response["error"]
  end

  test "should update user profile with valid params" do
    patch "/api/v1/user",
          params: {
            user: {
              first_name: "Updated",
              last_name: "Name",
              email: "updated@example.com",
              username: "updated_user"
            }
          },
          headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Updated", json_response["first_name"]
    assert_equal "Name", json_response["last_name"]
    assert_equal "updated@example.com", json_response["email"]
    assert_equal "updated_user", json_response["username"]
    assert_equal "Profile updated successfully", json_response["message"]

    @user1.reload
    assert_equal "Updated", @user1.first_name
    assert_equal "Name", @user1.last_name
    assert_equal "updated@example.com", @user1.email
    assert_equal "updated_user", @user1.username
  end

  test "should update user profile with partial params" do
    patch "/api/v1/user",
          params: {
            user: {
              first_name: "NewFirst"
            }
          },
          headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "NewFirst", json_response["first_name"]
    assert_equal @user1.last_name, json_response["last_name"]

    @user1.reload
    assert_equal "NewFirst", @user1.first_name
  end

  test "should update password with confirmation via post user" do
    new_password = "newSecurePass99"

    post "/api/v1/user",
         params: {
           user: {
             password: new_password,
             password_confirmation: new_password
           }
         },
         headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Profile updated successfully", json_response["message"]

    @user1.reload
    assert @user1.valid_password?(new_password)
    assert_not @user1.valid_password?("password123")
  end

  test "should not update user profile with invalid email" do
    patch "/api/v1/user",
          params: {
            user: {
              email: "invalid_email"
            }
          },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not update user profile with duplicate email" do
    patch "/api/v1/user",
          params: {
            user: {
              email: @user2.email
            }
          },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not update user profile with duplicate username" do
    patch "/api/v1/user",
          params: {
            user: {
              username: @user2.username
            }
          },
          headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should not update user profile without authentication" do
    patch "/api/v1/user",
          params: {
            user: {
              first_name: "Updated"
            }
          }

    assert_response :unauthorized
    json_response = JSON.parse(response.body)
    assert_equal "Unauthorized", json_response["error"]
  end

  test "should search users by username" do
    get "/api/v1/users/search",
        params: { q: "user" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["users"].present?
    user_ids = json_response["users"].map { |u| u["id"] }
    assert_includes user_ids, @user2.id
    assert_not_includes user_ids, @user1.id
  end

  test "should search users with partial match" do
    get "/api/v1/users/search",
        params: { q: "john" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    user_ids = json_response["users"].map { |u| u["id"] }
    assert_includes user_ids, @user3.id
  end

  test "should not include current user in search results" do
    get "/api/v1/users/search",
        params: { q: @user1.username },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    user_ids = json_response["users"].map { |u| u["id"] }
    assert_not_includes user_ids, @user1.id
  end

  test "should limit search results to 20 users" do
    25.times do |i|
      User.create!(
        email: "user#{i}@example.com",
        password: "password123",
        password_confirmation: "password123",
        username: "testuser#{i}"
      )
    end

    get "/api/v1/users/search",
        params: { q: "testuser" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response["users"].length <= 20
  end

  test "should return user information in search results" do
    get "/api/v1/users/search",
        params: { q: @user2.username },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    user = json_response["users"].find { |u| u["id"] == @user2.id }
    assert_equal @user2.id, user["id"]
    assert_equal @user2.username, user["username"]
    assert_equal @user2.first_name, user["first_name"]
    assert_equal @user2.last_name, user["last_name"]
  end

  test "should require search query parameter" do
    get "/api/v1/users/search",
        params: {},
        headers: auth_headers(@token1)

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "Search query is required", json_response["error"]
  end

  test "should require search query to be present" do
    get "/api/v1/users/search",
        params: { q: "" },
        headers: auth_headers(@token1)

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "Search query is required", json_response["error"]
  end

  test "should require authentication for search" do
    get "/api/v1/users/search",
        params: { q: "test" }

    assert_response :unauthorized
  end

  test "should return empty array when no users match search" do
    get "/api/v1/users/search",
        params: { q: "nonexistentuser12345" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal [], json_response["users"]
  end

  test "should handle case insensitive search" do
    get "/api/v1/users/search",
        params: { q: "USER" },
        headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    user_ids = json_response["users"].map { |u| u["id"] }
    assert_includes user_ids, @user2.id
  end

  test "should show baby_name and daily_nap_count" do
    @user1.update!(baby_name: "Emma", daily_nap_count: 4)

    get "/api/v1/user", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Emma", json_response["baby_name"]
    assert_equal 4, json_response["daily_nap_count"]
    assert_nil json_response["daily_nap_count_alt"]
  end

  test "should update baby_name and daily_nap_count" do
    post "/api/v1/user",
         params: {
           user: {
             baby_name: "Liam",
             daily_nap_count: 2
           }
         },
         headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "Liam", json_response["baby_name"]
    assert_equal 2, json_response["daily_nap_count"]

    @user1.reload
    assert_equal "Liam", @user1.baby_name
    assert_equal 2, @user1.daily_nap_count
  end

  test "should update and clear daily_nap_count_alt" do
    post "/api/v1/user",
         params: {
           user: {
             daily_nap_count: 2,
             daily_nap_count_alt: 3
           }
         },
         headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 2, json_response["daily_nap_count"]
    assert_equal 3, json_response["daily_nap_count_alt"]

    post "/api/v1/user",
         params: {
           user: {
             daily_nap_count: 3,
             daily_nap_count_alt: nil
           }
         },
         headers: auth_headers(@token1),
         as: :json

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 3, json_response["daily_nap_count"]
    assert_nil json_response["daily_nap_count_alt"]

    @user1.reload
    assert_equal 3, @user1.daily_nap_count
    assert_nil @user1.daily_nap_count_alt
  end

  test "should reject invalid daily_nap_count_alt range" do
    post "/api/v1/user",
         params: {
           user: {
             daily_nap_count: 2,
             daily_nap_count_alt: 4
           }
         },
         headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should reject daily_nap_count outside 1 to 5" do
    post "/api/v1/user",
         params: {
           user: {
             daily_nap_count: 6
           }
         },
         headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should show and update baby_birthdate" do
    birthdate = 6.months.ago.to_date
    @user1.update!(baby_birthdate: birthdate)

    get "/api/v1/user", headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal birthdate.iso8601, json_response["baby_birthdate"]

    new_birthdate = 1.year.ago.to_date
    post "/api/v1/user",
         params: { user: { baby_birthdate: new_birthdate.iso8601 } },
         headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal new_birthdate.iso8601, json_response["baby_birthdate"]
    assert_equal new_birthdate, @user1.reload.baby_birthdate
  end

  test "should reject future baby_birthdate" do
    post "/api/v1/user",
         params: { user: { baby_birthdate: 1.day.from_now.to_date.iso8601 } },
         headers: auth_headers(@token1)

    assert_response :unprocessable_entity
    json_response = JSON.parse(response.body)
    assert json_response["errors"].present?
  end

  test "should update user with POST method" do
    post "/api/v1/user",
         params: {
           user: {
             first_name: "POSTUpdated"
           }
         },
         headers: auth_headers(@token1)

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "POSTUpdated", json_response["first_name"]

    @user1.reload
    assert_equal "POSTUpdated", @user1.first_name
  end
end

