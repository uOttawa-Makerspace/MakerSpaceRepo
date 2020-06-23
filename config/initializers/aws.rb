# frozen_string_literal: true

require 'aws-sdk'
Aws::VERSION =  Gem.loaded_specs["aws-sdk"].version

Aws.config.update({
                      region: Rails.application.credentials[Rails.env.to_sym][:aws][:region],
                      credentials: Aws::Credentials.new(Rails.application.credentials[Rails.env.to_sym][:aws][:access_key_id], Rails.application.credentials[Rails.env.to_sym][:aws][:secret_access_key])
                  })
