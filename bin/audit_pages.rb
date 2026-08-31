Rails.application.eager_load!

puts "\n" + "=" * 80
puts "PAGE & ASSET AUDIT REPORT"
puts "=" * 80

routes = Rails.application.routes.routes.map do |r|
  {
    controller: r.defaults[:controller],
    action: r.defaults[:action],
    path: r.path.spec.to_s
  }
end.compact.uniq { |r| r[:controller] }.reject { |r| r[:controller].nil? || r[:controller].start_with?("rails/") }

routes.each do |route|
  c_path = route[:controller]
  c_name = c_path.split("/").last
  
  # Check for matching JS entrypoint
  js_entrypoint = [
    "app/javascript/entrypoints/#{c_name}.js",
    "app/javascript/entrypoints/#{c_path.tr('/', '_')}.js"
  ].find { |f| File.exist?(f) }

  # Check for matching SCSS stylesheet
  scss_file = [
    "app/javascript/stylesheets/#{c_name}.scss",
    "app/javascript/stylesheets/_#{c_name}.scss",
    "app/javascript/stylesheets/#{c_path.tr('/', '_')}.scss",
    "app/javascript/stylesheets/_#{c_path.tr('/', '_')}.scss"
  ].find { |f| File.exist?(f) }

  puts "\n[PATH] #{route[:path]}"
  puts "  Controller: #{c_path}"
  puts "  JS Entrypoint : #{js_entrypoint ? "✓ #{js_entrypoint}" : "- None"}"
  puts "  SCSS File     : #{scss_file ? "✓ #{scss_file}" : "- None"}"
end
puts "\n" + "=" * 80