require 'aws-sdk'

if Rails.env.eql?("development")
  Aws.config.update({
      region: 'us-west-2',
      credentials: Aws::Credentials.new(ENV.fetch('AWS_ACCESS_KEY_ID', "wrong"), ENV.fetch('AWS_SECRET_ACCESS_KEY', "wrong"))
  })
else
  Aws.config.update({
      region: 'us-west-2',
      credentials: Aws::Credentials.new(Rails.application.secrets.access_key_id, Rails.application.secrets.secret_access_key)
  })
end