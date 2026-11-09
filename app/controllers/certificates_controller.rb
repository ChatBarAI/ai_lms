class CertificatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_course

  def show
    @enrollment = current_user.enrollments.find_by(course: @course)

    @certificate = Certificate.find_by(user: current_user, course: @course)

    return head :forbidden if @certificate&.revoked?

    unless @certificate || @enrollment&.fully_completed?
      redirect_to course_path(@course),
                  alert: t("catalog_ui.certificate_incomplete", **helpers.terms)
      return
    end

    @certificate ||= Certificate.find_or_issue(user: current_user, course: @course)

    respond_to do |format|
      format.html
      format.pdf do
        pdf_data = CertificatePdfService.new(@certificate).generate
        send_data pdf_data,
                  filename:    "certificate-#{@course.slug}.pdf",
                  type:        "application/pdf",
                  disposition: :attachment
      end
    end
  end

  private

  def set_course
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    authorize! :read, @course
  end
end
