module MaterialDesignRevisionsHelper
  def material_design_revision_status_classes(status)
    case status
    when "ready"
      "bg-green-100 text-green-800"
    when "failed"
      "bg-red-100 text-red-800"
    when "generating"
      "bg-amber-100 text-amber-800"
    when "accepted"
      "bg-indigo-100 text-indigo-800"
    else
      "bg-gray-100 text-gray-700"
    end
  end
end
