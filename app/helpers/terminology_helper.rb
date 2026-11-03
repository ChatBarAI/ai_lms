module TerminologyHelper
  # The terminology values (%{lesson}, %{courses_l}, ...) for direct use, e.g. `= terms[:courses]`.
  # `t(...)` fills these placeholders on its own (config/initializers/terminology.rb); never pass `**terms` to it.
  def terms
    TerminologyInterpolation.values(I18n.locale)
  end
end
