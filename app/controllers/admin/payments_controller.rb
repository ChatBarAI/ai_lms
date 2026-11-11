class Admin::PaymentsController < Admin::BaseController
  def index
    @page = [ params[:page].to_i, 1 ].max
    @purchases = Purchase.includes(:user, :course).order(id: :desc).limit(50).offset((@page - 1) * 50)
    @events = PaymentEvent.unfinished.order(:created_at).limit(50)
    @grants = CourseEntitlement.includes(:user, :course, :entitlement_events).order(id: :desc).limit(100)
  end

  def show
    @purchase = Purchase.find(params[:id])
    @grant = @purchase.course_entitlement
  end

  def retry
    PurchaseReconciliationJob.perform_later(Purchase.find(params[:id]).id)
    redirect_to admin_payment_path(params[:id]), notice: t("payments.processing")
  end

  def retry_event
    PaymentEventJob.perform_later(PaymentEvent.find(params.require(:event_id)).id)
    redirect_to admin_payments_path, notice: t("payments.processing")
  end

  def grant
    Entitlements::Grant.call(user: User.find(params.require(:user_id)), course: Course.find(params.require(:course_id)),
      source: "manual", reference: params.require(:reference), reason: params.require(:reason), actor: current_user,
      expires_at: params[:expires_at].presence && Time.zone.parse(params[:expires_at]))
    redirect_to admin_payments_path, notice: t("payments.saved")
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    redirect_to admin_payments_path, alert: e.message
  end

  def revoke
    Entitlements::Transition.call(grant: CourseEntitlement.find(params.require(:grant_id)), action: "revoke",
      source: "manual", reason: params.require(:reason), reference: SecureRandom.uuid, actor: current_user)
    redirect_to admin_payments_path, notice: t("payments.saved")
  end
end
