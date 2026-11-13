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
    app/views/admin/add_new_staff/index.html.erb
    app/views/admin/announcements/edit.html.erb
    app/views/admin/announcements/index.html.erb
    app/views/admin/announcements/new.html.erb
    app/views/admin/announcements/show.html.erb
    app/views/admin/cc_moneys/index.html.erb
    app/views/admin/contact_infos/edit.html.erb
    app/views/admin/contact_infos/index.html.erb
    app/views/admin/contact_infos/new.html.erb
    app/views/admin/contact_infos/_opening_hour_form.html.erb
    app/views/admin/deleted_repositories/index.html.erb
    app/views/admin/design_days/_design_day_schedule_form.html.erb
    app/views/admin/design_days/show.html.erb
    app/views/admin/drop_off_locations/edit.html.erb
    app/views/admin/drop_off_locations/index.html.erb
    app/views/admin/drop_off_locations/new.html.erb
    app/views/admin/job_options/edit.html.erb
    app/views/admin/job_options/_form.html.erb
    app/views/admin/job_options/new.html.erb
    app/views/admin/job_service_groups/edit.html.erb
    app/views/admin/job_service_groups/_form.html.erb
    app/views/admin/job_service_groups/new.html.erb
    app/views/admin/job_services/edit.html.erb
    app/views/admin/job_services/_form.html.erb
    app/views/admin/job_services/new.html.erb
    app/views/admin/job_types/edit.html.erb
    app/views/admin/job_types/_form.html.erb
    app/views/admin/job_types/new.html.erb
    app/views/admin/keys/assign.html.erb
    app/views/admin/keys/edit.html.erb
    app/views/admin/keys/history.html.erb
    app/views/admin/keys/index.html.erb
    app/views/admin/keys/_keys_requests_table.html.erb
    app/views/admin/keys/_keys_table.html.erb
    app/views/admin/keys/new.html.erb
    app/views/admin/keys/requests.html.erb
    app/views/admin/keys/revoke.html.erb
    app/views/admin/key_transactions/edit.html.erb
    app/views/admin/key_transactions/index.html.erb
    app/views/admin/key_transactions/_key_transaction_table.html.erb
    app/views/admin/key_transactions/show.html.erb
    app/views/admin/memberships/index.html.erb
    app/views/admin/settings/index.html.erb
    app/views/admin/teams/edit.html.erb
    app/views/admin/teams/index.html.erb
    app/views/admin/teams/new.html.erb
    app/views/admin/teams/show.html.erb
    app/views/admin/time_periods/edit.html.erb
    app/views/admin/time_periods/_form.html.erb
    app/views/admin/time_periods/index.html.erb
    app/views/admin/time_periods/new.html.erb
    app/views/admin/index.html.erb
    app/views/admin/users/index.html.erb
    app/views/admin/users/search.html.erb
    app/views/admin/users/show.html.erb
    app/views/admin/users/edit.html.erb
    app/views/admin/users/manage_roles.erb
    app/views/admin/users/_user_table.html.erb
    app/views/admin/spaces/index.html.erb
    app/views/admin/spaces/edit.html.erb
    app/views/admin/trainings/index.html.erb
    app/views/admin/trainings/new.html.erb
    app/views/admin/trainings/edit.html.erb
    app/views/admin/trainings/_form.html.erb
    app/views/admin/training_sessions/index.html.erb
    app/views/admin/training_sessions/_training_session_table.html.erb
    app/views/admin/certifications/show.html.erb
    app/views/admin/certifications/demotions.html.erb
    app/views/admin/certifications/_table_demotions.html.erb
    app/views/admin/certifications/_certification_modal.html.erb
    app/views/admin/skills/index.html.erb
    app/views/admin/skills/new.html.erb
    app/views/admin/skills/edit.html.erb
    app/views/admin/uni_programs/index.html.erb
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
