class Admin::CertificatesController < Admin::BaseController
  def index
    @q            = Certificate.ransack(params[:q])
    @q.sorts      = "issued_at desc" if @q.sorts.empty?
    certificates  = @q.result(distinct: true)
                       .includes(:user, course: :subject)
    @pagy, @certificates = pagy(:offset, certificates)
  end

  def destroy
    @certificate = Certificate.find(params[:id])
    @certificate.destroy!
    redirect_to admin_certificates_path, notice: "Certificate revoked."
  end
end
