# frozen_string_literal: true

namespace :slugs_for_project_proposals do

  desc 'Create/Update slugs for project proposal'
  task create: :environment do
    ProjectProposal.all.each do |pp|
      pp.update(slug: "#{pp.id.to_s}.#{pp.title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')}")
    end
  end
end
