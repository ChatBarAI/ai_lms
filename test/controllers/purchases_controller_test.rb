require "test_helper"

class PurchasesControllerTest < ActionDispatch::IntegrationTest
  test "another buyer cannot view or reconcile a purchase" do
    purchase = Purchase.create!(user: users(:student), course: courses(:algebra), account_id: "acct_test", livemode: false,
      course_title: "Algebra", amount_minor: 1000, currency: "eur", tax_mode: "exempt", tax_behavior: "exclusive",
      return_base_url: "https://lms.example", attempt_key: "attempt", eligibility: { eligible: true })
    sign_in users(:other_student)
    get purchase_path(purchase)
    assert_response :not_found
  end

  test "ordinary learners cannot access financial administration or issue grants" do
    sign_in users(:student)
    get admin_payments_path
    assert_redirected_to root_path
    assert_no_difference "CourseEntitlement.count" do
      post grant_admin_payments_path, params: { user_id: users(:student).id, course_id: courses(:algebra).id,
        reference: "forged", reason: "forged" }
    end
    assert_redirected_to root_path
  end
end
