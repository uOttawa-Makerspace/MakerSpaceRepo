# frozen_string_literal: true

require "rails_helper"

# Templates whose wording lives in config/locales. A literal English sentence, label or
# attribute added to one of them fails here; add a locale key (English and French) instead.
# Add a template to the list when it is converted.
RSpec.describe "Translated templates" do
  TRANSLATED_TEMPLATES = %w[
    app/views/static_pages/about.html.erb
    app/views/static_pages/contact.html.erb
    app/views/licenses/_license.html.erb
    app/views/licenses/common_creative_attribution.html.erb
    app/views/licenses/common_creative_attribution_share_alike.html.erb
    app/views/licenses/common_creative_attribution_no_derivatives.html.erb
    app/views/licenses/common_creative_attribution_non_commercial.html.erb
    app/views/licenses/attribution_non_commercial_share_alike.html.erb
    app/views/licenses/attribution_non_commercial_no_derivatives.html.erb
    app/views/layouts/license.html.erb
    app/views/layouts/getting_started.html.erb
    app/views/getting_started/setting_up_account.html.erb
    app/views/getting_started/creating_repository.html.erb
    app/views/users/confirm.html.erb
    app/views/users/unlock_account.html.erb
    app/views/users/resend_confirmation.html.erb
  ].freeze

  # Names and addresses that are the same in every language.
  ALLOWED_LITERALS = ["@uOCEED", "@uoceed", "CEED", "makerepo.com/new", "MakerRepo"].freeze

  # Markup with ERB output, comments, scripts, tags and entities removed leaves only visible text.
  def visible_literals(source)
    stripped = source.gsub(/<%#.*?%>/m, "").gsub(/<%.*?%>/m, " ").gsub(/<script.*?<\/script>/m, "")
    stripped.gsub(/<[^>]*>/m, " ").gsub(/&\w+;/, " ").split(/\s+/).grep(/[[:alpha:]]/) - ALLOWED_LITERALS
  end

  # A quoted English string handed to a helper that renders it, such as link_to 'Text', path.
  def literal_arguments(source)
    source.scan(/(?:link_to|button_to|label_tag|submit_tag|provide|placeholder:|title:|aria-label:)\s*\(?[:\w]*,?\s*(['"])([^'"]*[A-Za-z]{2}[^'"]*)\1/)
      .map(&:last).reject { |text| ALLOWED_LITERALS.include?(text) || text.match?(%r{\A(https?:|/|#)}) }
  end

  TRANSLATED_TEMPLATES.each do |path|
    it "#{path} has no literal text" do
      source = Rails.root.join(path).read

      expect(visible_literals(source)).to eq([])
      expect(literal_arguments(source)).to eq([])
    end
  end
end
