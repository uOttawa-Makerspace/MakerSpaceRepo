require "rails_helper"

RSpec.describe KeyRequestDenyFormComponent, type: :component do
  let(:key_request) { build_stubbed(:key_request) }

  def render_form(**options)
    render_inline(described_class.new(key_request: key_request, **options))
  end

  it "posts to the deny URL for the request and asks for confirmation" do
    render_form

    form = page.find("form")
    expect(form["action"]).to eq("/admin/keys/deny_key_request?id=#{key_request.id}")
    expect(form).to have_css("button[disabled][data-controller='confirmation'][data-confirmation-message-value='Are you sure you want to deny this key request?']")
    expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
  end

  it "pairs a visually hidden label with a reason field whose id is unique per request" do
    render_form

    field_id = "denial_reason_#{key_request.id}"
    expect(page).to have_css("label.visually-hidden[for='#{field_id}']", text: "Reason for denying (optional)")
    expect(page).to have_field("denial_reason", id: field_id, type: "text")
    expect(page.find("##{field_id}")["maxlength"]).to eq(KeyRequest::MAX_DENIAL_REASON_LENGTH.to_s)
  end

  it "uses a different field id for another request" do
    other = build_stubbed(:key_request)
    render_inline(described_class.new(key_request: other))

    expect(page).to have_css("label[for='denial_reason_#{other.id}']")
    expect(page).to have_no_css("##{"denial_reason_#{key_request.id}"}")
  end

  it "applies the given classes and shows the icon only when asked" do
    render_form(form_class: "d-flex", input_class: "form-control-sm", button_class: "btn-danger", icon: true)

    expect(page).to have_css("form.d-flex input.form-control.form-control-sm")
    expect(page).to have_css("button.btn-danger", text: "Deny")
    expect(page).to have_css("button i.bi-x-lg")
  end

  it "has no icon by default" do
    render_form

    expect(page).to have_no_css("i.bi-x-lg")
  end
end
