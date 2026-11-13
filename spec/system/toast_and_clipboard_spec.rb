# frozen_string_literal: true

require "rails_helper"

# The Bootstrap toast helper (src/toast.js) and the copy buttons (src/clipboard.js)
# in a real browser. navigator.clipboard.writeText is replaced by a recorder so
# the copied text can be asserted without clipboard permissions.
RSpec.describe "Toasts and copy buttons", type: :system do
  def record_clipboard_writes
    page.execute_script(<<~JS)
      window.clipboardWrites = [];
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: (text) => { window.clipboardWrites.push(text); return Promise.resolve(); } },
      });
    JS
  end

  def clipboard_writes
    page.evaluate_script("window.clipboardWrites")
  end

  describe "toast when changing the staff space fails" do
    let(:space) { create(:space) }
    let(:staff) { create(:user, :staff, space: space) }

    before do
      log_in_as(staff, to: staff_dashboard_index_path)
    end

    it "shows the server's error message in a Bootstrap toast" do
      page.execute_script(<<~JS)
        window.fetch = () => Promise.resolve(new Response(JSON.stringify({ error: "Space is closed" }), { status: 422 }));
      JS
      page.execute_script("window.setSpace()")

      expect(page).to have_css("#toast-container .toast.text-bg-danger.show", text: "Space is closed")
    end

    it "falls back to a generic message and can be closed" do
      page.execute_script(<<~JS)
        window.fetch = () => Promise.resolve(new Response("{}", { status: 500 }));
      JS
      page.execute_script("window.setSpace()")

      expect(page).to have_css("#toast-container .toast.show", text: "Could not change space")
      find("#toast-container .toast.show .btn-close").click
      expect(page).to have_no_css("#toast-container .toast")
    end

    it "shows a success toast with a link when a server response asks for one" do
      page.execute_script(<<~JS)
        document.dispatchEvent(new CustomEvent("toast:show", {
          detail: { message: "Item added to Cart. Go to ", type: "success", link: { text: "Checkout", href: "/carts" } },
        }));
      JS

      expect(page).to have_css(
        "#toast-container .toast.text-bg-success.show",
        text: "Item added to Cart. Go to Checkout"
      )
      expect(page).to have_link("Checkout", href: "/carts")
    end
  end

  describe "copy button on the discount codes page" do
    let(:user) { create(:user, :volunteer_with_dev_program) }
    let!(:coupon) { create(:coupon_code, :claimed, user: user, code: "SAVE-1234") }

    before do
      log_in_as(user, to: discount_codes_path)
      record_clipboard_writes
    end

    it "copies the code and shows the copied popover" do
      find(".clipboard-btn", text: "Copy").click

      expect(clipboard_writes).to eq(["SAVE-1234"])
      expect(page).to have_css(".popover", text: "Copied !")
    end
  end

  describe "copy buttons on the volunteer emails page" do
    let(:staff) { create(:user, :staff) }
    let!(:volunteer) { create(:user, :volunteer_with_volunteer_program, email: "vol-one@example.com") }

    before do
      log_in_as(staff, to: emails_volunteers_path)
      record_clipboard_writes
    end

    it "copies the emails listed on the page" do
      click_on "Copy All Emails"

      expect(clipboard_writes.size).to eq(1)
      expect(clipboard_writes.first).to include("vol-one@example.com")
    end
  end
end
