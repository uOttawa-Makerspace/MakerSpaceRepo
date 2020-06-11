if Rails.env.eql?("development")
  S3DirectUpload.config do |c|
    c.access_key_id = ENV.fetch('AWS_ACCESS_KEY_ID', "wrong")
    c.secret_access_key = ENV.fetch('AWS_SECRET_ACCESS_KEY', "wrong")
    c.bucket = ENV.fetch('S3_BUCKET_NAME', "makerspace-testing-for-real")
    c.region = ENV.fetch('AWS_REGION', "us-west-2")
    c.url = "https://#{c.bucket}.s3.amazonaws.com/"
  end
else
  S3DirectUpload.config do |c|
    c.access_key_id = Rails.application.secrets.access_key_id
    c.secret_access_key = Rails.application.secrets.secret_access_key
    c.bucket = Rails.application.secrets.s3_bucket_name
    c.region = "us-west-2"
    c.url = "https://#{c.bucket}.s3.amazonaws.com/"
  end
end