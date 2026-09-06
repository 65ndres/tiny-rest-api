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

  test "allows 0 and 6 daily naps without alt" do
    [0, 6].each do |count|
      @user.daily_nap_count = count
      @user.daily_nap_count_alt = nil

      assert @user.valid?, "expected #{count} naps to be valid"
    end
  end

  test "rejects unsupported nap count ranges" do
    @user.daily_nap_count = 2
    @user.daily_nap_count_alt = 4

    refute @user.valid?
    assert_includes @user.errors[:daily_nap_count_alt], "must be an allowed nap range"
  end

  test "rejects daily_nap_count outside 0 to 6" do
    @user.daily_nap_count = 7

    refute @user.valid?
    assert @user.errors[:daily_nap_count].present?
  end

  test "allows baby_birthdate within the last 5 years" do
    @user.baby_birthdate = 4.years.ago.to_date

    assert @user.valid?
  end

  test "rejects baby_birthdate older than 5 years" do
    @user.baby_birthdate = 5.years.ago.to_date - 1.day

    refute @user.valid?
    assert_includes @user.errors[:baby_birthdate], "must be within the last 5 years"
  end
end

