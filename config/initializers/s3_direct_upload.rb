# frozen_string_literal: true

S3DirectUpload.config do |c|
  c.access_key_id = Rails.application.credentials[Rails.env.to_sym][:aws][:access_key_id]
  c.secret_access_key = Rails.application.credentials[Rails.env.to_sym][:aws][:secret_access_key]
  c.bucket = Rails.application.credentials[Rails.env.to_sym][:aws][:bucket_name]
  c.region = Rails.application.credentials[Rails.env.to_sym][:aws][:region]
  c.url = "https://#{c.bucket}.s3.amazonaws.com/"
end