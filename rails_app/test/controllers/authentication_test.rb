require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "an unauthenticated request to a protected route redirects to sign-in" do
    get chats_path

    assert_redirected_to new_session_path
  end

  test "signing in after being redirected lands back on the originally-requested page" do
    get chats_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: users(:one).email_address, password: "password" }

    assert_redirected_to chats_path
  end

  test "signing in with no prior redirect lands on the root page" do
    post session_path, params: { email_address: users(:one).email_address, password: "password" }

    assert_redirected_to root_path
  end

  test "/monitoring redirects to sign-in when unauthenticated" do
    get monitoring_path

    assert_redirected_to new_session_path
  end

  test "/evaluation redirects to sign-in when unauthenticated" do
    get evaluation_path

    assert_redirected_to new_session_path
  end

  test "there is no registration route" do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/users", method: :post) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/users/new", method: :get) }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/signup", method: :get) }
  end

  test "there is no password-reset route" do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/passwords/new", method: :get) }
  end
end
