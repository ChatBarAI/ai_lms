class CoursePurchaseFulfillmentService
  def initialize(session_id)
    @session_id = session_id
  end

  def call
    stripe_session = Stripe::Checkout::Session.retrieve(@session_id)
    return if stripe_session.payment_status == "unpaid"
    return if CoursePurchase.exists?(stripe_session_id: @session_id)

    user   = User.find(stripe_session.metadata.user_id)
    course = Course.find(stripe_session.metadata.course_id)

    CoursePurchase.create!(
      user: user,
      course: course,
      amount_cents: stripe_session.amount_total,
      stripe_session_id: @session_id,
      stripe_payment_intent_id: stripe_session.payment_intent
    )

    enrollment = Enrollment.find_or_initialize_by(user: user, course: course)
    enrollment.role ||= :student
    enrollment.save!
  end
end
