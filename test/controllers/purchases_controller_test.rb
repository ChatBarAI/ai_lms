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

  test "buyer sees each purchase status with the amount actually charged" do
    course = Course.create!(title: "Paid course", owner: users(:instructor), published_at: 1.day.ago,
      access_policy: "entitlement_required", price_minor: 1000, price_currency: "eur")
    purchase = Purchase.create!(user: users(:other_student), course: course, account_id: "acct_test", livemode: false,
      course_title: "Paid course", amount_minor: 1000, currency: "eur", tax_mode: "automatic", tax_behavior: "exclusive",
      return_base_url: "https://lms.example", attempt_key: "status-page", eligibility: { eligible: true })
    sign_in users(:other_student)

    get purchase_path(purchase)
    assert_response :success
    assert_select "[role=status]", text: I18n.t("payments.processing")
    assert_select "dd", text: "EUR 10.00"
    assert_select "a[href=?]", purchase_path(purchase), text: I18n.t("payments.refresh")

    get purchase_path(purchase, cancelled: 1)
    assert_select "[role=status]", text: I18n.t("payments.cancelled")

    purchase.update_columns(payment_state: "expired")
    get purchase_path(purchase)
    assert_select "[role=status]", text: I18n.t("payments.expired")

    purchase.update_columns(payment_state: "refunded")
    get purchase_path(purchase)
    assert_select "[role=status]", text: I18n.t("payments.access_required")

    purchase.update_columns(payment_state: "paid", fulfilment_state: "exception", total_minor: 1190, tax_minor: 190, base_minor: 1000)
    get purchase_path(purchase)
    assert_select "[role=status]", text: I18n.t("payments.support_needed")
    assert_select "dd", text: "EUR 11.90"

    Entitlements::Grant.call(user: users(:other_student), course: course, source: "manual", reference: "status-page",
      actor: users(:admin), reason: "Support")
    purchase.update_columns(fulfilment_state: "fulfilled")
    get purchase_path(purchase)
    assert_select "[role=status]", text: I18n.t("payments.success")
    assert_select "a[href=?]", course_path(course), text: I18n.t("payments.start_learning")
  end
end
