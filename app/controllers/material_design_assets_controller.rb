class MaterialDesignAssetsController < ApplicationController
  before_action :authenticate_user!, except: [ :file, :imported_file ]
  before_action :set_nested_context, only: [ :create, :update, :destroy, :destroy_imported ]

  def create
    authorize! :manage, @lesson_material
    asset = @lesson_material.material_design_assets.new(asset_params.merge(created_by: current_user))
    asset.role = requested_role if requested_role.present?
    destination = if params[:return_to] == "new_design"
      new_course_lesson_lesson_material_material_design_revision_path(
        @course, @lesson, @lesson_material,
        parent_revision_id: params[:parent_revision_id].presence
      )
    else
      course_lesson_lesson_material_material_design_revisions_path(
        @course, @lesson, @lesson_material
      )
    end

    if asset.save
      label = asset.video? ? "Video" : "Image"
      redirect_to destination, notice: "#{label} uploaded as #{asset.role.humanize.downcase}."
    else
      redirect_to destination, alert: asset.errors.full_messages.to_sentence
    end
  end

  def update
    authorize! :manage, @lesson_material
    asset = @lesson_material.material_design_assets.find(params[:id])

    asset.role = requested_role
    if asset.save
      redirect_to course_lesson_lesson_material_material_design_revisions_path(
        @course, @lesson, @lesson_material
      ), notice: "Asset is now a #{asset.role.humanize.downcase}."
    else
      redirect_to course_lesson_lesson_material_material_design_revisions_path(
        @course, @lesson, @lesson_material
      ), alert: asset.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize! :manage, @lesson_material
    @lesson_material.material_design_assets.find(params[:id]).destroy
    redirect_to destination, notice: "Asset removed.", status: :see_other
  end

  def destroy_imported
    authorize! :manage, @lesson_material
    attachment_id = ActiveStorage.verifier.verified(
      params[:id], purpose: :material_design_imported_asset
    )
    attachment = @lesson_material.imported_assets.attachments.find(attachment_id)
    attachment.purge

    redirect_to destination, notice: "Image removed.", status: :see_other
  end

  def file
    asset = MaterialDesignAsset.find_signed!(params[:id], purpose: :material_design_asset)
    authorize! :read, asset.lesson_material
    raise ActiveRecord::RecordNotFound unless asset.file.attached?

    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Pragma"] = "no-cache"
    redirect_to rails_blob_path(asset.file, disposition: "inline"), allow_other_host: false
  end

  def imported_file
    attachment_id = ActiveStorage.verifier.verified(
      params[:id], purpose: :material_design_imported_asset
    )
    raise ActiveRecord::RecordNotFound if attachment_id.blank?

    attachment = ActiveStorage::Attachment.find(attachment_id)
    unless attachment.record_type == "LessonMaterial" && attachment.name == "imported_assets"
      raise ActiveRecord::RecordNotFound
    end

    authorize! :read, attachment.record
    redirect_to rails_blob_path(attachment.blob, disposition: "inline"), allow_other_host: false
  end

  private

  def destination
    return course_lesson_lesson_material_material_design_revisions_path(
      @course, @lesson, @lesson_material
    ) unless params[:return_to] == "new_design"

    new_course_lesson_lesson_material_material_design_revision_path(
      @course, @lesson, @lesson_material,
      parent_revision_id: params[:parent_revision_id].presence
    )
  end

  def set_nested_context
    @course = Course.find_by(slug: params[:course_id]) || Course.find(params[:course_id])
    @lesson = @course.lessons.find(params[:lesson_id])
    @lesson_material = @lesson.lesson_materials.find(params[:lesson_material_id])
  end

  def asset_params
    params.require(:material_design_asset).permit(:name, :description, :alt_text, :file)
  end

  def requested_role
    params.require(:material_design_asset)[:role].to_s.presence
  end
end
