require "test_helper"

class CoursePurchasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @course = courses(:algebra)
    @course.update!(price_cents: 1999)
  end

  teardown do
    @course.update!(price_cents: nil)
  end

  test "unauthenticated user is redirected to login on POST create" do
    post course_purchase_path(@course)
    assert_redirected_to new_user_session_path
  end

  test "unauthenticated user is redirected to login on GET success" do
    get success_course_purchase_path(@course, session_id: "cs_test_123")
    assert_redirected_to new_user_session_path
  end

  test "unauthenticated user is redirected to login on GET cancel" do
    get cancel_course_purchase_path(@course)
    assert_redirected_to new_user_session_path
  end

  test "already-purchased user is redirected with notice" do
    CoursePurchase.create!(user: users(:student), course: @course, amount_cents: 1999)
    sign_in users(:student)

    post course_purchase_path(@course)

    assert_redirected_to course_path(@course)
    assert_equal "You already have access to this course.", flash[:notice]
  end

  test "cancel redirects to course with alert" do
    sign_in users(:student)

    get cancel_course_purchase_path(@course)

    assert_redirected_to course_path(@course)
    assert_equal "Payment was cancelled.", flash[:alert]
  end

  test "success with blank session_id redirects with alert" do
    sign_in users(:student)

    get success_course_purchase_path(@course)

    assert_redirected_to course_path(@course)
    assert_equal "Invalid payment session.", flash[:alert]
  end

  test "create initiates Stripe checkout and redirects to checkout URL" do
    sign_in users(:student)

    fake_customer = Struct.new(:id).new("cus_test")
    fake_session  = Struct.new(:url).new("https://checkout.stripe.com/pay/cs_test_123")

    Stripe::Customer.stub(:create, fake_customer) do
      Stripe::Checkout::Session.stub(:create, fake_session) do
        post course_purchase_path(@course)
      end
    end

    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_123"
  end

  test "create shows alert when Stripe raises an error" do
    sign_in users(:student)

    fake_customer = Struct.new(:id).new("cus_test")

    Stripe::Customer.stub(:create, fake_customer) do
      Stripe::Checkout::Session.stub(:create, ->(*) { raise Stripe::StripeError, "card declined" }) do
        post course_purchase_path(@course)
      end
    end

    assert_redirected_to course_path(@course)
    assert_match "Payment error", flash[:alert]
  end
end
