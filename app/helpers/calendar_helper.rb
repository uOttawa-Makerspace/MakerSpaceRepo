module CalendarHelper
  def generate_color_from_id(id, opacity = 1.0)
    hash = if id.to_i.zero?
      id.to_s.match?(/^\d+$/) ? id.to_i : id.to_s.each_byte.reduce(0) { |sum, b| sum * 31 + b }
    else
      id.to_i
    end

    h = (hash * 137.5) % 360
    s = 80 + (hash % 15)
    l = 50 + (hash % 10)

    # Convert HSL to RGB
    c = (1 - (2 * l / 100.0 - 1).abs) * s / 100.0
    x = c * (1 - ((h / 60.0) % 2 - 1).abs)
    m = l / 100.0 - c / 2.0
    r, g, b = [ [c,x,0], [x,c,0], [0,c,x], [0,x,c], [x,0,c], [c,0,x] ][(h / 60).to_i % 6]
    r = ((r + m) * 255).round
    g = ((g + m) * 255).round
    b = ((b + m) * 255).round

    # Calculate contrast ratio with white
    contrast_ratio = contrast_with_white(r, g, b)

    while contrast_ratio < 3 && l > 18
      l -= 5
      c = (1 - (2 * l / 100.0 - 1).abs) * s / 100.0
      x = c * (1 - ((h / 60.0) % 2 - 1).abs)
      m = l / 100.0 - c / 2.0
      r, g, b = [ [c,x,0], [x,c,0], [0,c,x], [0,x,c], [x,0,c], [c,0,x] ][(h / 60).to_i % 6]
      r = ((r + m) * 255).round
      g = ((g + m) * 255).round
      b = ((b + m) * 255).round
      contrast_ratio = contrast_with_white(r, g, b)
    end

    "rgba(#{r}, #{g}, #{b}, #{opacity})"
  end

  def contrast_with_white(r, g, b)
    # Relative luminance of the color
    rgb = [r, g, b].map do |c|
      c /= 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4
    end
    l1 = 1.0 # luminance of white
    l2 = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2] # luminance of the color

    (l1 + 0.05) / (l2 + 0.05)
  end

end
