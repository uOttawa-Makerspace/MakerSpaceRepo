# frozen_string_literal: true

# Finds literal English text in an ERB template: visible words, text attributes and quoted
# strings handed to helpers that render them.
module LiteralTextScan
  # Names and addresses that are the same in every language.
  ALLOWED_LITERALS = ["@uOCEED", "@uoceed", "CEED", "makerepo.com", "MakerRepo.com", "makerepo.com/new", "MakerRepo", "MAKERREPO",
                      "email@uottawa.ca"].freeze

  LITERAL_ARGUMENT = /
    (?<helper>link_to|button_to|button_tag|label_tag|submit_tag|provide|tag\.\w+|content_tag|(?<![.\w'"])\w+\.(?:label|submit)\b|
       (?:placeholder|prompt|title|alt|value|label|aria-label|default):)
    \s*\(?\s*(?::\w+,\s*)?(?<quote>['"])(?<text>(?:\\.|(?!\k<quote>)[^\\])*[A-Za-z]{2}(?:\\.|(?!\k<quote>)[^\\])*)\k<quote>
  /x

  # Helpers whose quoted argument can be a form token instead of wording: the submitted value of a
  # button (value: 'active') or the field a label is for (label_tag 'assign_indefinite').
  FIELD_TOKEN_HELPERS = ["value:", "label_tag"].freeze

  # A lower-case form code such as "await_payment" or "brunsfield-centre": submitted, not shown.
  FORM_CODE = /\A[a-z0-9_-]+\z/

  # A tag, read past any ">" inside its quoted attribute values (such as data-action="input->search#filter").
  TAG = /<(?:[^>"']|"[^"]*"|'[^']*')*>/m

  # Markup with ERB output, comments, scripts, styles, tags and entities removed leaves only visible text.
  # A path shown as written (such as /learning_area/s/) is the same in every language.
  def self.visible_literals(source)
    stripped = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, " ").gsub(/<!--.*?-->/m, " ").gsub(%r{<script.*?</script>}m, "")
                     .gsub(%r{<style.*?</style>}m, "")
    words = stripped.gsub(TAG, " ").gsub(/&\w+;/, " ").split(/\s+/).grep(/[[:alpha:]]/)
    words.grep_v(%r{\A/[\w/]*\z}) - ALLOWED_LITERALS
  end

  # Text-bearing HTML attributes written out in the markup, such as alt="Logo" or placeholder="Email". A value
  # that is one lower-case token (value="events", value="brunsfield-centre") is a form code that is submitted, not shown.
  def self.literal_attributes(source)
    markup = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, "")
    found = markup.scan(/\b(alt|title|aria-label|placeholder|value|label)=(["'])([^"']*[A-Za-z]{2}[^"']*)\2/)
    found.reject { |name, _, text| name == "value" && text.match?(FORM_CODE) }.map(&:last) - ALLOWED_LITERALS
  end

  def self.literal_arguments(source)
    source.scan(LITERAL_ARGUMENT).reject { |helper, _, text| field_token?(helper, text) }.map(&:last)
          .reject { |text| ALLOWED_LITERALS.include?(text) || not_wording?(text) }
  end

  # A lowercase identifier such as "await_payment" handed to a helper that takes form tokens.
  def self.field_token?(helper, text)
    FIELD_TOKEN_HELPERS.include?(helper) && text.match?(FORM_CODE)
  end

  # Links, fragments, markup with no text outside its tags, and a string that is one interpolation (optionally after an id prefix).
  def self.not_wording?(text)
    text.match?(%r{\A(https?:|/|#)}) || text.match?(/\A(\w+_)?#\{[^}]*\}\z/) || markup_without_text?(text)
  end

  def self.markup_without_text?(text)
    text.start_with?("<") && text.gsub(/<[^>]*>/, "").gsub(/#\{[^}]*\}/, "").match?(/\A[^[:alpha:]]*\z/)
  end
end
