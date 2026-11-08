require "rails_helper"

# The editor markup the app has always rendered, saved as a fixture so the
# local helper can be checked against it.
RSpec.describe TrixFieldsHelper, type: :helper do
  let(:fixture_path) { Rails.root.join("spec/fixtures/trix_editor_markup.yml") }
  let(:faq) { Faq.new(body_en: %(<div>Hello &amp; <strong>welcome</strong> "q"</div>), body_fr: nil) }

  def render_cases # rubocop:disable Metrics/AbcSize
    cases = {}
    TrixFieldsHelper.id = 0
    helper.form_with(model: faq, url: "/faqs", scope: :faq) do |f|
      cases["builder_class"] = f.trix_editor(:body_en, class: "form-control")
      cases["builder_style_required"] =
        f.trix_editor(:body_fr, class: "form-control", style: "height: auto!important;", required: true)
      cases["builder_placeholder_id_aria"] =
        f.trix_editor(
          :body_en,
          placeholder: "Description...",
          class: "form-control mb-5",
          id: "redactor",
          'aria-label': "Description"
        )
      ""
    end
    helper.form_with(model: faq, url: "/faqs", scope: :faq) do |f|
      f.fields_for(:nested, faq) do |h|
        cases["fields_for"] = h.trix_editor(:body_en, class: "repo form-control", style: "height: auto!important;")
      end
      ""
    end
    TrixFieldsHelper.id = 0
    cases["tag_print_failed"] =
      helper.trix_editor_tag(
        "print_failed_message[staff_notes]",
        {},
        { id: "print_failed_message_staff_notes", class: "form-control" }
      )
    cases["tag_value_and_class_array"] =
      helper.trix_editor_tag("note", "<p>x</p>", class: %w[a b], placeholder: "p")
    cases
  end

  it "renders the same markup as the saved fixture" do
    expect(render_cases).to eq(YAML.load_file(fixture_path))
  end
end
