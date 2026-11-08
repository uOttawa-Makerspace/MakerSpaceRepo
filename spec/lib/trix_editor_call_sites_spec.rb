require "rails_helper"

# Rich text belongs in Action Text (has_rich_text / rich_text_area). The Trix
# helpers stay only for the fields that already use them; new rich text fields
# must not add more call sites.
RSpec.describe "trix_editor call sites" do
  it "does not grow in app/views" do
    sites =
      Dir[Rails.root.join("app/views/**/*")].select { |f| File.file?(f) }.sum do |file|
        File.foreach(file).count { |line| line.match?(/\btrix_editor(_tag)?\b/) && !line.match?(/<%#/) }
      end

    expect(sites).to be <= 23
  end
end
