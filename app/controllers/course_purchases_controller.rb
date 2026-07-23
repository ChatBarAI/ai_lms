class CoursePurchasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_course
  before_action :set_stripe_key

  # POST /courses/:course_id/purchase
  # Creates a Stripe Checkout Session (one-time payment) and redirects.
  def create
    if @course.purchased_by?(current_user)
      return redirect_to @course, notice: "You already have access to this course."
    end

    session = create_stripe_checkout_session
    redirect_to session.url, allow_other_host: true
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe error for course purchase: #{e.message}"
    redirect_to @course, alert: "Payment error: #{e.message}"
  end

  # GET /courses/:course_id/purchase/success?session_id=...
  # Stripe redirects here after successful payment.
  def success
    session_id = params[:session_id]
    return redirect_to @course, alert: "Invalid payment session." if session_id.blank?

    handle_payment_success(session_id)
    redirect_to @course, notice: "Payment successful! You now have access to this course."
  rescue Stripe::StripeError => e
    Rails.logger.error "Stripe callback error for course: #{e.message}"
    redirect_to @course, alert: "Payment confirmed but could not activate access. Please contact support."
  end

  # GET /courses/:course_id/purchase/cancel
  def cancel
    redirect_to @course, alert: "Payment was cancelled."
  end

  private

  def set_course
    @course = Course.find_by!(slug: params[:course_id]) rescue Course.find(params[:course_id])
  end

  def set_stripe_key
    Stripe.api_key = Rails.configuration.stripe[:secret_key]
  end

  def create_stripe_checkout_session
    customer = get_or_create_stripe_customer

    Stripe::Checkout::Session.create(
      payment_method_types: [ "card" ],
      customer: customer.id,
      line_items: [ {
        price_data: {
          currency: "usd",
          product_data: {
            name: @course.title,
            description: @course.description&.truncate(200)
          },
          unit_amount: @course.price_cents
        },
        quantity: 1
      } ],
      mode: "payment",
      success_url: "#{success_course_purchase_url(@course)}?session_id={CHECKOUT_SESSION_ID}&success=true",
      cancel_url: cancel_course_purchase_url(@course),
      metadata: {
        user_id: current_user.id,
        course_id: @course.id
      }
    )
  end

  def handle_payment_success(session_id)
    stripe_session = Stripe::Checkout::Session.retrieve(session_id)

    # Idempotent: skip if already recorded
    return if CoursePurchase.exists?(stripe_session_id: session_id)

    CoursePurchase.create!(
      user: current_user,
      course: @course,
      amount_cents: stripe_session.amount_total,
      stripe_session_id: session_id,
      stripe_payment_intent_id: stripe_session.payment_intent
    )

    # Automatically enrol the user after purchase
    enrollment = Enrollment.find_or_initialize_by(user: current_user, course: @course)
    enrollment.role ||= :student
    enrollment.save!
  end

  def get_or_create_stripe_customer
    if current_user.stripe_customer_id.present?
      Stripe::Customer.retrieve(current_user.stripe_customer_id)
    else
      customer = Stripe::Customer.create(
        email: current_user.email,
        name: current_user.name.presence || current_user.email,
        metadata: { user_id: current_user.id }
      )
      current_user.update_column(:stripe_customer_id, customer.id)
      customer
    end
  end
end
