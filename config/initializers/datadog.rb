Datadog.configure do |c|
  c.env = 'production'
  c.service = 'MakerRepo'
  c.sampling.default_rate = 1.0
end