class MaterialDesignRevisionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_context
  before_action :authorize_material!
  before_action :set_revision, only: [ :show, :preview, :accept, :destroy ]

  def index
    @revisions = @lesson_material.material_design_revisions
                                 .includes(:ai_model_configuration)
                                 .recent
    load_design_assets
  end

  def new
    parent_revision = @lesson_material.material_design_revisions.find_by(
      id: params[:parent_revision_id]
    )
    @revision = @lesson_material.material_design_revisions.new(
      parent_revision: parent_revision,
      ai_model_configuration: parent_revision&.ai_model_configuration || AiModelConfiguration.enabled.first,
      request: parent_revision&.request
    )
    load_design_assets
  end

  def create
    @revision = @lesson_material.material_design_revisions.new(revision_params)
    @revision.parent_revision = @lesson_material.material_design_revisions.find_by(
      id: @revision.parent_revision_id
    )
    @revision.created_by = current_user
    @revision.status = "queued"
    @revision.source_html = source_html_for(@revision)

    if @revision.save
      @revision.broadcast_status
      MaterialDesignGenerationJob.perform_later(@revision.id)
      redirect_to course_lesson_lesson_material_material_design_revisions_path(
        @course, @lesson, @lesson_material
      ), notice: "Design revision queued."
    else
      load_design_assets
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    @revision.errors.add(:base, "A design generation is already in progress for this material.")
    load_design_assets
    render :new, status: :unprocessable_entity
  end

  def show
  end

  def source_preview
    parent_revision = @lesson_material.material_design_revisions.find_by(
      id: params[:parent_revision_id]
    )
    revision = @lesson_material.material_design_revisions.new(parent_revision: parent_revision)
    source_html = source_html_for(revision)

    LessonMaterialsController::DOCUMENT_RESPONSE_HEADERS.each do |name, value|
      response.headers[name] = value
    end
    response.headers.delete("X-Frame-Options")
    render html: source_preview_html(source_html).html_safe,
           layout: false,
           content_type: "text/html"
  end

  def preview
    raise ActiveRecord::RecordNotFound unless @revision.ready? || @revision.accepted?

    LessonMaterialsController::DOCUMENT_RESPONSE_HEADERS.each do |name, value|
      response.headers[name] = value
    end
    response.headers.delete("X-Frame-Options")
    render html: @revision.sanitized_html.to_s.html_safe, layout: false, content_type: "text/html"
  end

  def accept
    @revision.accept!
    redirect_to edit_course_lesson_lesson_material_path(@course, @lesson, @lesson_material),
                notice: "AI design revision accepted and applied to the material."
  rescue ActiveRecord::RecordInvalid
    redirect_to course_lesson_lesson_material_material_design_revision_path(
      @course, @lesson, @lesson_material, @revision
    ), alert: "Only a ready revision can be accepted."
  end

  def destroy
    @revision.destroy!
    redirect_to course_lesson_lesson_material_material_design_revisions_path(
      @course, @lesson, @lesson_material
    ), notice: "Design revision deleted.", status: :see_other
  end

  private

  def set_context
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
    @lesson_material = @lesson.lesson_materials.find(params[:lesson_material_id])
  end

  def authorize_material!
    authorize! :manage, @lesson_material
  end

  def set_revision
    @revision = @lesson_material.material_design_revisions.find(params[:id])
  end

  def revision_params
    params.require(:material_design_revision)
          .permit(:request, :ai_model_configuration_id, :parent_revision_id)
  end

  def load_design_assets
    @assets = @lesson_material.material_design_assets.includes(file_attachment: :blob)
    @imported_assets = MaterialDesignAssetCatalog.new(@lesson_material).entries.select do |asset|
      asset.source == :imported
    end
    @asset = @lesson_material.material_design_assets.new(role: :content)
  end

  def source_html_for(revision)
    return revision.parent_revision.sanitized_html if revision.parent_revision.present?
    return if @lesson_material.blank_ai_design_source?

    @lesson_material.raw_html_content.presence || @lesson_material.body.to_s.presence
  end

  def source_preview_html(source_html)
    return source_html if source_html.present?

    <<~HTML
      <!doctype html>
      <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body><p style="font-family: system-ui; color: #6b7280; padding: 1rem;">No source document. This revision will start from zero.</p></body>
      </html>
    HTML
  end
end
