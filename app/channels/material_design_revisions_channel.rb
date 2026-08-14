class MaterialDesignRevisionsChannel < ApplicationCable::Channel
  def subscribed
    lesson_material = LessonMaterial.find_by(id: params[:lesson_material_id])

    unless lesson_material && Ability.new(current_user).can?(:manage, lesson_material)
      reject
      return
    end

    stream_from MaterialDesignRevision.stream_name_for(lesson_material.id)
    transmit({
      event: "snapshot",
      revisions: lesson_material.material_design_revisions.recent.map do |revision|
        MaterialDesignRevision.broadcast_payload(revision)
      end
    })
  end
end
