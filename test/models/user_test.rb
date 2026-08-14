require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      email: "nap_range@example.com",
      password: "password123",
      password_confirmation: "password123",
      username: "naprangeuser",
      first_name: "Nap",
      last_name: "Parent"
    )
  end

  test "allows exact daily_nap_count without alt" do
    @user.daily_nap_count = 3
    @user.daily_nap_count_alt = nil

    assert @user.valid?
  end

  test "allows supported nap count ranges" do
    User::ALLOWED_NAP_COUNT_RANGES.each do |lower, upper|
      @user.daily_nap_count = lower
      @user.daily_nap_count_alt = upper

      assert @user.valid?, "expected #{lower} or #{upper} naps to be valid"
    end
  end

  test "rejects unsupported nap count ranges" do
    @user.daily_nap_count = 4
    @user.daily_nap_count_alt = 5

    refute @user.valid?
    assert_includes @user.errors[:daily_nap_count_alt], "must be an allowed nap range"
  end
end
