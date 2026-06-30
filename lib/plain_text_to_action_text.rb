module PlainTextToActionText
  module_function

  def html_for(plain_text)
    text = plain_text.to_s
    return "" if text.blank?

    text.split(/\r?\n\r?\n+/).map do |paragraph|
      escaped = ERB::Util.html_escape(paragraph).gsub("\n", "<br>")
      "<p>#{escaped}</p>"
    end.join
  end
end
