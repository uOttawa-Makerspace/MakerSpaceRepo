# bin/diagnose_assets.rb
puts "\n" + "=" * 80
puts "DIAGNOSTIC 1: CHECKING SCSS FILES FOR CONTROLLER / BODY WRAPPERS"
puts "=" * 80

scss_files = Dir.glob("app/javascript/stylesheets/**/*.scss")
scss_files.each do |file|
  lines = File.readlines(file)
  body_selectors = lines.select { |l| l =~ /(body\.[a-zA-Z0-9_-]+|\.[a-zA-Z0-9_-]+\s*\{)/ }
  
  if body_selectors.any?
    puts "\n📁 #{file}"
    body_selectors.first(3).each do |match|
      puts "   ↳ Expects wrapper/class: #{match.strip}"
    end
  end
end

puts "\n" + "=" * 80
puts "DIAGNOSTIC 2: CHECKING JS ENTRYPOINTS FOR COMMONJS / SYNTAX ISSUES"
puts "=" * 80

js_files = Dir.glob("app/javascript/entrypoints/**/*.js")
js_files.each do |file|
  content = File.read(file)
  issues = []
  issues << "Uses CommonJS 'require()' (Vite requires ES6 'import')" if content.match?(/\brequire\s*\(/)
  issues << "Uses 'module.exports' (Vite requires ES6 'export')" if content.match?(/\bmodule\.exports\b/)
  issues << "Direct jQuery '$' reference without import" if content.match?(/\$\([\"'\`]/) && !content.match?(/import.*from\s+['"]jquery['"]/)

  if issues.any?
    puts "\n⚠️  #{file}:"
    issues.each { |issue| puts "   ↳ #{issue}" }
  end
end
puts "\n" + "=" * 80