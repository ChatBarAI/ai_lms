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
    precision = Payments::Currency::RULES.fetch(course.price_currency, [ 2 ]).first
    number_to_currency(BigDecimal(course.price_minor.to_s) / (10 ** precision), unit: course.price_currency.upcase + " ", precision: precision)
  end
end
