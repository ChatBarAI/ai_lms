module PaymentsHelper
  def course_access_available?(course)
    return true unless course.paid?
    return false unless current_user
    return true if current_user.admin? || course.owner_id == current_user.id
    # One grant query per rendered request, rather than per catalogue card.
    @effective_payment_course_ids ||= CourseEntitlement.effective.where(user_id: current_user.id).pluck(:course_id).to_set
    @effective_payment_course_ids.include?(course.id)
  end

  def course_price_label(course)
    return t("payments.free") unless course.paid?
    return t("payments.access_available") if course_access_available?(course)
    course_price_amount(course)
  end

  # Amount actually charged for a purchase, e.g. "USD 25.00".
  def purchase_amount_label(purchase)
    precision = Payments::Currency::RULES.fetch(purchase.currency, [ 2 ]).first
    number_to_currency(BigDecimal(purchase.amount_minor.to_s) / (10 ** precision), unit: purchase.currency.upcase + " ", precision: precision)
  end

  # Presentation for the purchase status page. Class strings are written out in
  # full so Tailwind can detect them.
  def purchase_status(purchase)
    key =
      if purchase.fulfilment_state == "fulfilled" && course_access_available?(purchase.course) then :success
      elsif purchase.fulfilment_state == "exception" then :support
      elsif %w[refunded disputed lost].include?(purchase.payment_state) then :locked
      elsif purchase.payment_state == "expired" then :expired
      elsif params[:cancelled] then :cancelled
      else :processing
      end
    message = { success: "success", support: "support_needed", locked: "access_required",
      expired: "expired", cancelled: "cancelled", processing: "processing" }.fetch(key)
    tone = {
      success: { ring: "border-green-500/70", badge_class: "bg-green-600 text-white", icon: "bg-green-100 text-green-700", accent: "text-green-600" },
      processing: { ring: "border-indigo-400/70", badge_class: "bg-indigo-600 text-white", icon: "bg-indigo-50 text-indigo-600", accent: "text-indigo-600" },
      cancelled: { ring: "border-amber-400/70", badge_class: "bg-amber-500 text-white", icon: "bg-amber-100 text-amber-700", accent: "text-amber-600" },
      expired: { ring: "border-amber-400/70", badge_class: "bg-amber-500 text-white", icon: "bg-amber-100 text-amber-700", accent: "text-amber-600" },
      support: { ring: "border-red-400/70", badge_class: "bg-red-600 text-white", icon: "bg-red-100 text-red-600", accent: "text-red-600" },
      locked: { ring: "border-red-400/70", badge_class: "bg-red-600 text-white", icon: "bg-red-100 text-red-600", accent: "text-red-600" }
    }.fetch(key)
    { key: key, message: t("payments.#{message}"), badge: t("payments.status.#{key}.badge"),
      heading: t("payments.status.#{key}.heading"), accent_text: t("payments.status.#{key}.accent") }.merge(tone)
  end

  def purchase_status_icon(key)
    path = case key
    when :success then "M5 13l4 4L19 7"
    when :processing then "M12 6v6l4 2m6-2a10 10 0 11-20 0 10 10 0 0120 0z"
    when :cancelled, :expired then "M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
    else "M12 9v3.75m0 3.75h.008M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"
    end
    tag.svg(tag.path(d: path, "stroke-linecap": "round", "stroke-linejoin": "round"),
      class: "w-7 h-7", fill: "none", stroke: "currentColor", "stroke-width": "2", viewBox: "0 0 24 24", "aria-hidden": "true")
  end

  # Price with its currency code (e.g. "USD 25.00"), regardless of the viewer's access.
  def course_price_amount(course)
    return t("payments.free") unless course.paid?
    precision = Payments::Currency::RULES.fetch(course.price_currency, [ 2 ]).first
    number_to_currency(BigDecimal(course.price_minor.to_s) / (10 ** precision), unit: course.price_currency.upcase + " ", precision: precision)
  end
end
