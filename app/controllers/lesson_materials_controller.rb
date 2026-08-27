class LessonMaterialsController < ApplicationController
  DOCUMENT_CONTENT_SECURITY_POLICY = [
    "default-src 'none'",
    "img-src 'self' data:",
    "media-src 'self'",
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
  before_action :normalize_copy_kind, only: :create
  before_action :normalize_ai_designed_kind, only: :create
  load_and_authorize_resource through: :lesson
  skip_authorize_resource only: [ :acknowledge, :reorder, :document, :copy ]

  def index
    @lesson_materials = @lesson.lesson_materials
  end

  def show
  end

  def new
    @chatbar_token_prefilled = @lesson.cbai_token.present?
    @lesson_material.chatbar_token ||= @lesson.cbai_token
    @copy_source_catalog = copy_source_catalog
  end

  def copy
    destination = LessonMaterial.new(lesson: @lesson)
    authorize! :create, destination

    source = LessonMaterial.find(params.require(:source_material_id))
    authorize! :manage, source

    copied_material = LessonMaterialCopyService.new(
      source: source,
      destination_lesson: @lesson,
      copied_by: current_user,
      copy_settings: ActiveModel::Type::Boolean.new.cast(params[:copy_settings])
    ).call

    if ActiveModel::Type::Boolean.new.cast(params[:open_in_designer]) && copied_material.ai_designable?
      redirect_to new_course_lesson_lesson_material_material_design_revision_path(
        @course, @lesson, copied_material
      ), notice: "Material copied. Describe how the AI designer should adapt it."
    else
      redirect_to edit_course_lesson_lesson_material_path(@course, @lesson, copied_material),
                  notice: "Material copied."
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound
    redirect_to new_course_lesson_lesson_material_path(@course, @lesson),
                alert: "Choose a material to copy."
  rescue LessonMaterialCopyService::CopyError => error
    redirect_to new_course_lesson_lesson_material_path(@course, @lesson), alert: error.message
  end

  def create
    return copy if starting_material_copy?

    @lesson_material.lesson = @lesson
    prepare_ai_design_material if starting_ai_design?

    if persist_material
      if starting_ai_design?
        redirect_to new_course_lesson_lesson_material_material_design_revision_path(
          @course, @lesson, @lesson_material
        ), notice: "Material added. Describe what the AI designer should create."
      else
        redirect_to edit_course_lesson_path(@course, @lesson), notice: "Material added."
      end
    else
      @copy_source_catalog = copy_source_catalog
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
    redirect_to edit_course_lesson_path(@course, @lesson, open_materials: 1),
                notice: "Material removed.", status: :see_other
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

  def copy_source_catalog
    courses = if current_user.admin?
      Course.includes(lessons: :lesson_materials).order(:title)
    else
      current_user.owned_courses.includes(lessons: :lesson_materials).order(:title)
    end

    courses.filter_map do |course|
      lessons = course.lessons.sort_by { |lesson| [ lesson.position.to_i, lesson.title.to_s ] }.filter_map do |lesson|
        materials = lesson.lesson_materials.map do |material|
          { id: material.id, title: material.title, kind: material.kind_label }
        end
        next if materials.empty?

        { id: lesson.id, title: lesson.title, materials: materials }
      end
      next if lessons.empty?

      { id: course.id, title: course.title, lessons: lessons }
    end
  end

  def set_course_and_lesson
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
  end

  def lesson_material_params
    params.require(:lesson_material).permit(:title, :kind, :position, :required, :open_by_default, :body, :document, :raw_html_content, :audio_file, :url, :image_file, :video_file, :google_doc_zip, :chatbar_token, :chatbar_prompt)
  end

  def starting_ai_design?
    @starting_ai_design == true
  end

  def starting_material_copy?
    @starting_material_copy == true
  end

  def normalize_copy_kind
    material_params = params[:lesson_material]
    return unless material_params&.[](:kind) == "copy"

    @starting_material_copy = true
    # Keep CanCanCan's resource loader on a valid persisted enum. The placeholder
    # is never saved because #create delegates to the copy workflow.
    material_params[:kind] = "pdf"
  end

  def normalize_ai_designed_kind
    material_params = params[:lesson_material]
    return unless material_params&.[](:kind) == "ai_designed"

    @starting_ai_design = true
    material_params[:kind] = "raw_html_iframe"
  end

  def prepare_ai_design_material
    @lesson_material.title = "Untitled material" if @lesson_material.title.blank?
    @lesson_material.kind = :raw_html_iframe
    @lesson_material.raw_html_content = LessonMaterial::AI_DESIGN_STARTER_HTML
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
