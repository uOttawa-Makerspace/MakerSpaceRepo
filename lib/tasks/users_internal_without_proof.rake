# frozen_string_literal: true

namespace :users do
  # Lists, by id only, the accounts whose identity is internal (uOttawa student, faculty or staff)
  # but which have no confirmed @uottawa.ca email, the only proof of a uOttawa affiliation.
  # It reads only and changes nothing.
  desc "List the ids of accounts with an internal identity and no proof of a uOttawa affiliation"
  task internal_without_proof: :environment do
    ids = User.internal_without_proof.order(:id).pluck(:id)
    ids.each { |id| puts id }
    puts "#{ids.size} accounts with an internal identity and no proof"
  end
end
