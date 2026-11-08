# frozen_string_literal: true

# The application stylesheet as the browser receives it (built by Vite for the
# test run), for specs that pin the rules actually emitted.
module CompiledStylesheet
  def compiled_css
    @compiled_css ||= begin
      path = ViteRuby.instance.manifest.path_for("application.scss", type: :stylesheet)
      Rails.public_path.join(path.delete_prefix("/")).read
    end
  end

  # Declarations of every rule whose selector list contains `selector`, merged
  # in order (later rules win), e.g. css_declarations(".fc .fc-button-primary").
  def css_declarations(selector)
    compiled_css.scan(/([^{}]*)\{([^{}]*)\}/).each_with_object({}) do |(selectors, body), found|
      next unless selector_list(selectors).include?(selector)

      body.split(";").each { |declaration| found.store(*declaration.split(":", 2).map(&:strip)) }
    end
  end

  private

  # Splits a selector list on the commas outside parentheses.
  def selector_list(selectors)
    selectors.scan(/(?:[^,(]|\([^)]*\))+/).map(&:strip)
  end
end

RSpec.configure { |config| config.include CompiledStylesheet }
