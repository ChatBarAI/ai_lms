class PurchasesController < ApplicationController
  before_action :authenticate_user!

  def create
    course = Course.find_by!(slug: params[:course_id])
    authorize! :read, course
    purchase = Payments::Checkout.new.call(user: current_user, course: course)
    return redirect_to course_path(course) unless purchase
    if purchase.payment_state == "pending" && purchase.checkout_url.present? && purchase.checkout_expires_at&.future?
      uri = URI.parse(purchase.checkout_url)
      raise Payments::Error, "Invalid checkout URL" unless uri.scheme == "https" && uri.host == "checkout.stripe.com"
      redirect_to purchase.checkout_url, allow_other_host: true, status: :see_other
    else
      redirect_to purchase_path(purchase), status: :see_other
    end
  rescue Payments::Error => e
    Rails.logger.warn("Checkout unavailable: #{e.class.name}")
    redirect_to course_path(course), alert: t("payments.unavailable")
  end

  def show
    @purchase = current_user.purchases.find(params[:id])
    begin
      Payments::Reconcile.new.call(@purchase) if @purchase.checkout_session_id.present?
    rescue Payments::Error
      flash.now[:alert] = t("payments.processing")
    end
    @purchase.reload
  end
end
