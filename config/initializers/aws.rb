# Aws.config(
#     access_key_id:      Rails.application.secrets.aws['access_key_id'],
#     secret_access_key:  Rails.application.secrets.aws['secret_access_key'],
#     bucket:             Rails.application.secrets.aws['s3_bucket_name']
# )
#
require 'aws-sdk'

Aws.config.update({
  region: 'us-west-2',
  credentials: Aws::Credentials.new(ENV.fetch('AWS_ACCESS_KEY_ID', "wrong"), ENV.fetch('AWS_SECRET_ACCESS_KEY', "wrong"))
})