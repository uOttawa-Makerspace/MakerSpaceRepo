# frozen_string_literal: true

namespace :api do
  desc "Delete /api/v1 refresh tokens expired or revoked more than 7 days ago"
  task prune_refresh_tokens: :environment do
    puts "Pruned #{ApiRefreshToken.prune!} api refresh token(s)"
  end
end
