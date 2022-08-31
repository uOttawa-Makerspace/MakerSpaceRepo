# frozen_string_literal: true

namespace :project_proposals do
  desc "Create/Update slugs for project proposal"
  task create_slugs: :environment do
    ProjectProposal.all.each do |pp|
      pp.update(
        slug:
          "#{pp.id.to_s}.#{pp.title.downcase.gsub(/[^0-9a-z ]/i, "").gsub(/\s+/, "-")}"
      )
    end
  end

  desc "Translate level of interest for project proposal"
  task translate_level_of_interest: :environment do
    ProjectProposal.all.each do |pp|
      case pp.client_interest
      when "Low"
        pp.update(client_interest: "Low / Faible")
      when "Medium"
        pp.update(client_interest: "Medium / Moyen")
      when "High"
        pp.update(client_interest: "High / Élevé")
      end
    end
  end

  desc "Translate client type for project proposal"
  task translate_client_type: :environment do
    ProjectProposal.all.each do |pp|
      case pp.client_type
      when "Organization"
        pp.update(client_type: "Organization / Organisation")
      when "Individual"
        pp.update(client_type: "Individual / Individuel")
      end
    end
  end

  desc "Change Wording for french client type"
  task change_wording_fr_client_type: :environment do
    ProjectProposal.all.each do |pp|
      if pp.client_type == "Individual / Particulier"
        pp.update(client_type: "Individual / Individuel")
      end
    end
  end
end
