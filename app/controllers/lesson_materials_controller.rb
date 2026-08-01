class LessonMaterialsController < ApplicationController
  DOCUMENT_CONTENT_SECURITY_POLICY = [
    "default-src 'none'",
    "img-src 'self' data:",
    "style-src 'unsafe-inline'",
    "font-src 'none'",
    "script-src 'none'",
    "connect-src 'none'",
    "frame-src 'none'",
    "form-action 'none'",
    "base-uri 'none'",
    "frame-ancestors 'self'"
  ].join("; ").freeze

  DOCUMENT_RESPONSE_HEADERS = {
    "Content-Security-Policy" => DOCUMENT_CONTENT_SECURITY_POLICY,
    "Content-Disposition" => "inline",
    "Cache-Control" => "private, no-store",
    "Referrer-Policy" => "no-referrer",
    "X-Content-Type-Options" => "nosniff"
  }.freeze

  before_action :authenticate_user!, except: [ :index, :show, :document ]
  before_action :set_course_and_lesson
  load_and_authorize_resource through: :lesson
  skip_authorize_resource only: [ :acknowledge, :reorder, :document ]

  def index
    @lesson_materials = @lesson.lesson_materials
  end

  def show
  end

  def new
  end

  def create
    @lesson_material.lesson = @lesson
    if persist_material
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @original_material_kind = @lesson_material.kind
    @lesson_material.assign_attributes(lesson_material_params)
    if persist_material
      redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lesson_material.destroy
    redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material removed.", status: :see_other
  end

  def reorder
    authorize! :manage, @lesson
    ids = Array(params[:ids]).map(&:to_i)
    materials = @lesson.lesson_materials.where(id: ids).index_by(&:id)
    LessonMaterial.transaction do
      ids.each_with_index do |id, idx|
        materials[id]&.update_column(:position, idx + 1)
      end
    end
    head :no_content
  end

  def acknowledge
    enrollment = current_user&.enrollments&.find_by(course_id: @course.id)
    unless enrollment
      redirect_to course_lesson_path(@course, @lesson), alert: "Enrol to mark materials as complete." and return
    end

    ack = LessonMaterialAcknowledgement.new(lesson_material_id: @lesson_material.id, enrollment_id: enrollment.id)
    authorize! :create, ack
    ack.save
    redirect_to course_lesson_path(@course, @lesson, anchor: "material-#{@lesson_material.id}"),
                notice: "Marked as complete."
  end

  def document
    authorize! :read, @lesson_material
    unless @lesson_material.google_doc? || @lesson_material.raw_html_iframe? || @lesson_material.web_page?
      raise ActiveRecord::RecordNotFound
    end

    DOCUMENT_RESPONSE_HEADERS.each do |name, value|
      response.headers[name] = value
    end
    response.headers.delete("X-Frame-Options")

    render html: @lesson_material.raw_html_content.to_s.html_safe,
           layout: false,
           content_type: "text/html"
  end

  private

  def set_course_and_lesson
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
  end

  def lesson_material_params
    params.require(:lesson_material).permit(:title, :kind, :position, :required, :open_by_default, :body, :document, :raw_html_content, :audio_file, :url, :image_file, :video_file, :google_doc_zip)
  end

  def persist_material
    if @lesson_material.web_page? && @lesson_material.url.present?
      WebPageImportService.new(material: @lesson_material).call
      return true
    end

    if @lesson_material.google_doc?
      if @lesson_material.google_doc_zip.present?
        GoogleDocImportService.new(
          material: @lesson_material,
          upload: @lesson_material.google_doc_zip
        ).call
        return true
      end

      if @original_material_kind == "google_doc"
        @lesson_material.restore_attributes([ :raw_html_content ])
      else
        # Imported document HTML can only be populated by the ZIP importer.
        @lesson_material.raw_html_content = nil
      end
    end

    @lesson_material.save
  rescue GoogleDocImportService::ImportError => error
    @lesson_material.errors.add(:google_doc_zip, error.message)
    false
  rescue WebPageImportService::ImportError => error
    @lesson_material.errors.add(:url, error.message)
    false
  rescue ActiveRecord::RecordInvalid
    false
  end
end
