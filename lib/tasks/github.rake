# frozen_string_literal: true

namespace :github do
  desc "Clear stored GitHub OAuth tokens (users.access_token) for every user. " \
       "GitHub account linking was removed, so these tokens are unused. DRY_RUN=1 only counts. " \
       "Idempotent. Tokens are NOT revoked at GitHub (no app credentials are configured); " \
       "users can revoke the app from their GitHub settings."
  task clear_tokens: :environment do
    scope = User.where.not(access_token: nil)
    count = scope.count

    # Fail-safe: ANY DRY_RUN value (even 0/false) only counts. The real run needs DRY_RUN unset.
    if ENV["DRY_RUN"].present?
      puts "[DRY RUN] #{count} user(s) have a stored GitHub access token; nothing changed."
    else
      # update_all: no callbacks, no updated_at change; users.access_token is the only GitHub column on users.
      cleared = scope.update_all(access_token: nil)
      puts "Cleared the GitHub access token for #{cleared} user(s). Tokens were not revoked at GitHub."
    end
  end
end
