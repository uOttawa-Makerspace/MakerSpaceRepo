Datadog.configure do |c|
  if Rails.env == "production"
    c.env = 'production'
    c.service = 'MakerRepo'
  elsif Rails.env == "staging"
    c.env = 'staging'
    c.service = 'MakerRepo Staging'
  end
  c.sampling.default_rate = 1.0
end