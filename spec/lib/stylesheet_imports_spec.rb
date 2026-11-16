require "rails_helper"

# Bootstrap is imported once, in application.scss. A second copy in a page
# stylesheet would be emitted after the app's own rules and replace them.
RSpec.describe "Stylesheet imports" do
  let(:styles) { Rails.root.join("app/javascript/stylesheets") }

  %w[settings.scss get_involved.scss].each do |file|
    it "#{file} does not import Bootstrap again" do
      expect(styles.join(file).read).not_to match(%r{@import\s+["']bootstrap})
    end
  end

  it "imports Bootstrap once in application.scss" do
    application = Rails.root.join("app/javascript/entrypoints/application.scss").read
    expect(application.scan(%r{@import\s+["']bootstrap/scss/bootstrap["']}).size).to eq(1)
  end
end

RSpec.describe "Links in running text" do
  let(:rule) { compiled_css[/(?<=\})main :is\(p,li,td\) a:not\([^{]*\)\{text-decoration:underline\}/] }

  it "are underlined in page content so colour is not the only cue" do
    expect(rule).to be_present
  end

  it "leave buttons, badges and navigation, pagination and tag links alone" do
    %w[.btn .badge .page-link nav .nav .tags .pagination .apple_pagination .breadcrumb .dropdown-menu .list-group].each do |skipped|
      expect(rule).to include(skipped)
    end
  end

  it "does not reach the footer or the navbars, which sit outside main" do
    expect(rule).to start_with("main ")
  end
end
