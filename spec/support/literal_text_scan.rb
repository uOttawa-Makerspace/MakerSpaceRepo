# frozen_string_literal: true

# Finds literal English text in an ERB template: visible words, text attributes and quoted
# strings handed to helpers that render them.
module LiteralTextScan
  # Names and addresses that are the same in every language.
  ALLOWED_LITERALS = ["@uOCEED", "@uoceed", "CEED", "makerepo.com/new", "MakerRepo"].freeze

  LITERAL_ARGUMENT = /
    (?:link_to|button_to|label_tag|submit_tag|provide|tag\.\w+|content_tag|
       (?:placeholder|title|alt|value|label|aria-label|default):)
    \s*\(?\s*(?::\w+,\s*)?(['"])((?:\\.|(?!\1)[^\\])*[A-Za-z]{2}(?:\\.|(?!\1)[^\\])*)\1
  /x

  # Markup with ERB output, comments, scripts, tags and entities removed leaves only visible text.
  def self.visible_literals(source)
    stripped = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, " ").gsub(%r{<script.*?</script>}m, "")
    stripped.gsub(/<[^>]*>/m, " ").gsub(/&\w+;/, " ").split(/\s+/).grep(/[[:alpha:]]/) - ALLOWED_LITERALS
  end

  # Text-bearing HTML attributes written out in the markup, such as alt="Logo" or placeholder="Email".
  def self.literal_attributes(source)
    markup = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, "")
    markup.scan(/\b(?:alt|title|aria-label|placeholder|value|label)=(["'])([^"']*[A-Za-z]{2}[^"']*)\1/).map(&:last) - ALLOWED_LITERALS
  end

  def self.literal_arguments(source)
    source.scan(LITERAL_ARGUMENT).map(&:last).reject { |text| ALLOWED_LITERALS.include?(text) || not_wording?(text) }
  end

  # Links, fragments, markup with no text outside its tags, and a string that is one interpolation (optionally after an id prefix).
  def self.not_wording?(text)
    text.match?(%r{\A(https?:|/|#)}) || text.match?(/\A(\w+_)?#\{[^}]*\}\z/) || markup_without_text?(text)
  end

  def self.markup_without_text?(text)
    text.start_with?("<") && text.gsub(/<[^>]*>/, "").gsub(/#\{[^}]*\}/, "").match?(/\A[^[:alpha:]]*\z/)
  end
end
