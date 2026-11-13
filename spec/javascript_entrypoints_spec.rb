# frozen_string_literal: true

require "spec_helper"

# Static check, no browser: every Vite entrypoint is loaded by something, and
# every Stimulus controller is referenced. A script nothing loads silently does
# nothing (the page keeps working without its enhancements), so this fails the
# build instead.
#
# An entrypoint is loaded when one of these holds:
# - a view names it in a vite_javascript_tag
# - a layout loads the entrypoint named after the request's controller_name
# - another script imports it
# A Stimulus controller is referenced when a view uses its identifier in
# data-controller, or a script looks it up by identifier.
RSpec.describe "JavaScript entrypoints and controllers" do
  root = File.expand_path("..", __dir__)
  js = File.join(root, "app/javascript")
  read = ->(path) { File.read(path, encoding: "UTF-8", invalid: :replace) }

  views = Dir[File.join(root, "app/views/**/*")].select { |f| File.file?(f) }.map(&read).join("\n")
  scripts = Dir[File.join(js, "**/*.{js,ts}")].to_h { |f| [f, read.call(f)] }
  controller_names = Dir[File.join(root, "app/controllers/**/*_controller.rb")].map { |f| File.basename(f, "_controller.rb") }
  explicit = views.scan(/vite_(?:javascript|typescript)_tag\s*\(?\s*['"]([\w\/.-]+)['"]/).flatten.map { |n| n.delete_suffix(".js") }

  it "has a loader for every entrypoint" do
    unloaded =
      Dir[File.join(js, "entrypoints/*.{js,ts}")].filter_map do |file|
        name = File.basename(file, ".*")
        next if explicit.include?(name) || controller_names.include?(name)

        import = /['"][.\/]*(entrypoints\/)?#{Regexp.escape(name)}(\.js|\.ts)?['"]/
        next if scripts.any? { |path, source| path != file && source.match?(import) }

        name
      end

    expect(unloaded).to be_empty, "entrypoints nothing loads: #{unloaded.join(", ")}"
  end

  it "references every Stimulus controller" do
    unused =
      Dir[File.join(js, "controllers/*_controller.{js,ts}")].filter_map do |file|
        identifier = File.basename(file).sub(/_controller\.(js|ts)\z/, "").tr("_", "-")
        pattern = /\b#{Regexp.escape(identifier)}\b/
        in_view = views.scan(/data-controller=["'][^"']*["']|controller[:=]\s*["'][^"']*["']/).any? { |m| m.match?(pattern) }
        in_script = scripts.any? { |path, source| path != file && source.match?(/["']#{Regexp.escape(identifier)}["']/) }

        identifier unless in_view || in_script
      end

    expect(unused).to be_empty, "Stimulus controllers nothing references: #{unused.join(", ")}"
  end
end
