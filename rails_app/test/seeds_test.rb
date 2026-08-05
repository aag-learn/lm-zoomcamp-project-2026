require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  SEEDS_FILE = Rails.root.join("db/seeds.rb")

  def with_admin_env(email:, password:)
    original_email = ENV["ADMIN_EMAIL"]
    original_password = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_EMAIL"] = email
    ENV["ADMIN_PASSWORD"] = password
    yield
  ensure
    ENV["ADMIN_EMAIL"] = original_email
    ENV["ADMIN_PASSWORD"] = original_password
  end

  test "running the seed twice with the same credentials creates exactly one User" do
    with_admin_env(email: "seed-idempotency@example.com", password: "first-password") do
      assert_difference("User.count", 1) { load SEEDS_FILE }
      assert_no_difference("User.count") { load SEEDS_FILE }
    end
  end

  test "re-running the seed with a rotated password updates the existing user, not a no-op" do
    with_admin_env(email: "seed-rotation@example.com", password: "old-password") do
      load SEEDS_FILE
    end

    user = User.find_by(email_address: "seed-rotation@example.com")
    assert user.authenticate("old-password")

    with_admin_env(email: "seed-rotation@example.com", password: "new-password") do
      assert_no_difference("User.count") { load SEEDS_FILE }
    end

    user.reload
    assert_not user.authenticate("old-password")
    assert user.authenticate("new-password")
  end
end
