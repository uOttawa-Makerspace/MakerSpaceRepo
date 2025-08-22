module BadgesHelper
  def word_wrap_badge_name(name, max_line_length = 20)
    words = name.split(' ')
    words.drop(1).reduce([words.first]) do |lines, word|
      # plus space
      if lines.last.length + word.length + 1 <= max_line_length
        lines[-1] = lines.last + ' ' + word
      else
        lines.append(word)
      end
      lines
    end
  end
end
