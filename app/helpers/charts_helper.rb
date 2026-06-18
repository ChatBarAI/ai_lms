module ChartsHelper
  # Renders a responsive inline SVG chart via the `chart` Stimulus controller.
  #
  # data: Hash or Array of [label, value] pairs. Date/Time keys are formatted as ISO.
  # type: :bar (horizontal), :column (vertical), :line
  def svg_chart(data, type:, color: "#4f46e5", height: 220, max: nil, suffix: "", empty_text: "No data yet.")
    pairs = normalize_chart_data(data)

    if pairs.empty?
      return content_tag(:div, empty_text, class: "text-sm text-gray-500 py-8 text-center")
    end

    content_tag :div, "",
      class: "chart",
      style: "height: #{height}px",
      data: {
        controller: "chart",
        chart_type_value: type.to_s,
        chart_data_value: pairs.to_json,
        chart_color_value: color,
        chart_max_value: max,
        chart_suffix_value: suffix
      }
  end

  private

  def normalize_chart_data(data)
    return [] if data.blank?

    pairs = data.respond_to?(:to_a) ? data.to_a : []
    pairs.map do |label, value|
      label_str =
        case label
        when Date     then label.strftime("%Y-%m-%d")
        when Time, DateTime, ActiveSupport::TimeWithZone then label.to_date.strftime("%Y-%m-%d")
        else label.to_s
        end
      [ label_str, value.to_f ]
    end
  end
end
