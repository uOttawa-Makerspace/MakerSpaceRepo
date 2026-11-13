# frozen_string_literal: true

require "rails_helper"

# Templates whose wording lives in config/locales. A literal English sentence, label or
# attribute added to one of them fails here; add a locale key (English and French) instead.
# Add a template to the list when it is converted.
RSpec.describe "Translated templates" do
  TRANSLATED_TEMPLATES = %w[
    app/views/static_pages/about.html.erb
    app/views/static_pages/contact.html.erb
    app/views/static_pages/hours.html.erb
    app/views/static_pages/_opening_hours.html.erb
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
    app/views/search/explore.html.erb
    app/views/search/category.html.erb
    app/views/search/equipment.html.erb
    app/views/repositories/_repository_card.html.erb
    app/views/repositories/show.html.erb
    app/views/users/_repositories.html.erb
    app/views/staff_dashboard/index.html.erb
    app/views/staff_dashboard/search.html.erb
    app/views/staff_dashboard/_search.html.erb
    app/views/staff_dashboard/_signed_in_table.html.erb
    app/views/staff_dashboard/_signed_out_table.html.erb
    app/views/staff_dashboard/_space_activity_row.html.erb
    app/views/staff_dashboard/_newly_signed_up.html.erb
    app/views/staff_dashboard/_max_capacity_warning.html.erb
    app/views/staff_dashboard/_signin_modal.html.erb
    app/views/staff_dashboard/_flag.html.erb
    app/views/staff_dashboard/_flag_list.html.erb
    app/views/staff_dashboard/_no_assigned_spaces.html.erb
    app/views/staff_dashboard/_table_broadcast.turbo_stream.erb
  ].freeze

  TRANSLATED_TEMPLATES.each do |path|
    it "#{path} has no literal text" do
      source = Rails.root.join(path).read

      expect(LiteralTextScan.visible_literals(source)).to eq([])
      expect(LiteralTextScan.literal_attributes(source)).to eq([])
      expect(LiteralTextScan.literal_arguments(source)).to eq([])
    end
  end
end
