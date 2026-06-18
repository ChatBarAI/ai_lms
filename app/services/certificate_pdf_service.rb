require "prawn"

class CertificatePdfService
  # A4 landscape dimensions in points (72 pts/inch)
  PAGE_W = 841.89
  PAGE_H = 595.28
  DEFAULT_TEMPLATE_PATH = Rails.root.join("app/assets/images/chatbar-ai-certificate.jpg")

  def initialize(certificate)
    @cert    = certificate
    @user    = certificate.user
    @course  = certificate.course
    @setting = SiteSetting.current
  end

  def generate
    pdf = Prawn::Document.new(page_size: [ PAGE_W, PAGE_H ], margin: 0)
    # image_area is {x:, y_top:, w:, h:} describing the content rect in Prawn coords.
    # Fields are positioned as percentages of that rect, not the raw page.
    @image_area = draw_background(pdf)
    draw_fields(pdf)
    pdf.render
  end

  private

  # Background template (PNG / JPEG). Course template overrides the site default.
  # Returns the image content area {x:, y_top:, w:, h:} so field positions can
  # be mapped relative to the actual image, regardless of its aspect ratio.
  def draw_background(pdf)
    result = with_template_path do |path|
      img_w, img_h = image_dimensions(path)
      if img_w && img_h
        scale    = [ PAGE_W / img_w.to_f, PAGE_H / img_h.to_f ].min
        draw_w   = img_w * scale
        draw_h   = img_h * scale
        offset_x = (PAGE_W - draw_w) / 2.0
        offset_y = (PAGE_H - draw_h) / 2.0

        pdf.image path, at: [ offset_x, PAGE_H - offset_y ], width: draw_w, height: draw_h
        { x: offset_x, y_top: PAGE_H - offset_y, w: draw_w, h: draw_h }
      else
        pdf.image path, at: [ 0, PAGE_H ], width: PAGE_W, height: PAGE_H
        { x: 0, y_top: PAGE_H, w: PAGE_W, h: PAGE_H }
      end
    end
    result || { x: 0, y_top: PAGE_H, w: PAGE_W, h: PAGE_H }
  rescue Prawn::Errors::UnsupportedImageType
    { x: 0, y_top: PAGE_H, w: PAGE_W, h: PAGE_H }
  end

  def draw_fields(pdf)
    layout = @course.certificate_layout_with_defaults
    values = field_values

    Course::CERTIFICATE_FIELDS.each do |key|
      cfg  = layout[key]
      text = values[key]
      next if text.blank?

      render_field(pdf, text, cfg)
    end
  end

  def field_values
    {
      "name"           => @user.name.presence || @user.email,
      "course_title"   => @course.title,
      "date"           => I18n.l(@cert.issued_at.to_date, format: :long),
      "certificate_no" => "Certificate No: #{@cert.token}"
    }
  end

  # Anchor the text by its centre at (x%, y%) of the image content area.
  def render_field(pdf, text, cfg)
    size  = cfg["size"].to_f
    align = (cfg["align"] || "center").to_sym
    style = cfg["bold"] ? :bold : :normal
    x_pct = cfg["x"].to_f
    y_pct = cfg["y"].to_f

    area = @image_area
    box_w = area[:w] * 0.9
    box_h = size * 1.6

    center_x         = area[:x] + (x_pct / 100.0) * area[:w]
    center_y_from_top = (y_pct / 100.0) * area[:h]

    left      = center_x - (box_w / 2)
    top_prawn = area[:y_top] - center_y_from_top + (size * 0.25)

    pdf.fill_color "1a202c"
    pdf.font_size size do
      pdf.text_box text,
                   at:       [ left, top_prawn ],
                   width:    box_w,
                   height:   box_h,
                   align:    align,
                   overflow: :shrink_to_fit,
                   style:    style
    end
  end

  # Opens the active template and yields its temp-file path, or yields the
  # built-in asset path. Returns whatever the block returns, or nil.
  def with_template_path
    if @course.certificate_template.attached?
      @course.certificate_template.open { |f| yield f.path }
    elsif @setting.certificate_template.attached?
      @setting.certificate_template.open { |f| yield f.path }
    elsif File.exist?(DEFAULT_TEMPLATE_PATH)
      yield DEFAULT_TEMPLATE_PATH.to_s
    end
  end

  # Returns [width, height] in pixels using Ruby's built-in string parsing —
  # no extra gems required for JPEG/PNG.
  def image_dimensions(path)
    data = File.binread(path, 24)
    if data[0, 8] == "\x89PNG\r\n\x1a\n"
      # PNG: width at bytes 16-19, height at 20-23 (big-endian)
      [ data[16, 4].unpack1("N"), data[20, 4].unpack1("N") ]
    elsif data[0, 2] == "\xFF\xD8"
      # JPEG: scan for SOF marker
      jpeg_dimensions(path)
    end
  rescue
    nil
  end

  def jpeg_dimensions(path)
    File.open(path, "rb") do |f|
      f.read(2) # SOI
      loop do
        marker = f.read(2)
        break unless marker&.start_with?("\xFF")
        code   = marker[1].ord
        length = f.read(2)&.unpack1("n")
        break unless length
        if (0xC0..0xC3).cover?(code) || (0xC5..0xC7).cover?(code) ||
           (0xC9..0xCB).cover?(code) || (0xCD..0xCF).cover?(code)
          f.read(1) # precision
          h = f.read(2).unpack1("n")
          w = f.read(2).unpack1("n")
          return [ w, h ]
        end
        f.seek(length - 2, IO::SEEK_CUR)
      end
    end
    nil
  end
end
