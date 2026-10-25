require "rails_helper"

# Chunk 15: PrinterIssuesController: reporting and resolving printer issues.
# StaffAreaController gate (guest -> login, regular/volunteer -> root alert);
# everything inside is open to any staff member except destroy (admin only,
# silent redirect for staff).
RSpec.describe "Printer issues", type: :request do
  include ActiveJob::TestHelper

  let!(:printer) { create(:printer, :UM2P_01) }
  let!(:issue) { create(:printer_issue, :nozzle_clogged, printer: printer) }

  def json
    JSON.parse(response.body)
  end

  describe "auth matrix" do
    GETS = %i[printer_issues_path new_printer_issue_path history_printer_issues_path].freeze

    GETS.each do |helper|
      it "#{helper}: guest -> login, regular -> root alert" do
        get send(helper)
        expect(response).to redirect_to(login_path(back_to: send(helper)))
        sign_in_as(:regular)
        get send(helper)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You cannot access this area.")
      end
    end

    it "blocks guests and regular users from create, update, destroy and update_notification_email" do
      expect { post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "x" } } }.not_to change(PrinterIssue, :count)
      patch printer_issue_path(issue), params: { printer_issue: { active: false } }
      expect(issue.reload.active).to be true
      expect { delete printer_issue_path(issue) }.not_to change(PrinterIssue, :count)
      patch update_notification_email_printer_issues_path, params: { notification_email: "a@b.c" }
      expect(Setting.maintenance_email).to be_blank
      sign_in_as(:regular)
      expect { post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "x" } } }.not_to change(PrinterIssue, :count)
      expect(response).to redirect_to(root_path)
      patch printer_issue_path(issue), params: { printer_issue: { active: false } }
      expect(issue.reload.active).to be true
    end
  end

  describe "as staff" do
    let!(:staff) { sign_in_as(:staff) }

    it "renders the index with issues grouped by summary" do
      get printer_issues_path
      expect(response).to have_http_status(:ok)
    end

    it "returns the issue list as JSON" do
      get printer_issues_path(format: :json)
      expect(json["issues"].first.keys).to match_array(%w[id printer_id reporter summary description created_at active])
      expect(json["issues"].first).to include("id" => issue.id, "printer_id" => printer.id, "active" => true, "reporter" => issue.reporter.name)
    end

    it "renders show, new, edit and the implicit history page" do
      get printer_issue_path(issue)
      expect(response).to have_http_status(:ok)
      get new_printer_issue_path
      expect(response).to have_http_status(:ok)
      get edit_printer_issue_path(issue)
      expect(response).to have_http_status(:ok)
      get history_printer_issues_path
      expect(response).to have_http_status(:ok)
    end

    # WART(D-EQ17): show for an unknown id uses find_by and renders the template with a nil @issue (500) instead of 404
    it "500s showing an unknown issue" do
      get printer_issue_path(0)
      expect(response).to have_http_status(:internal_server_error)
    end

    describe "POST create" do
      let(:params) { { printer_issue: { printer_id: printer.id, summary: "Bed issue: warped", description: "Corner lifts" } } }

      it "persists an active issue reported by the current user and redirects to it" do
        expect { post printer_issues_path, params: params }.to change(PrinterIssue, :count).by(1)
        created = PrinterIssue.last
        expect(response).to redirect_to(printer_issue_path(created))
        expect(created).to have_attributes(printer_id: printer.id, reporter_id: staff.id, active: true, summary: "Bed issue: warped", description: "Corner lifts")
      end

      it "emails nothing when no maintenance address is set" do
        ActionMailer::Base.deliveries.clear
        perform_enqueued_jobs { post printer_issues_path, params: params }
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it "delivers a notification to the maintenance address when set" do
        Setting.maintenance_email = "maint@example.com"
        ActionMailer::Base.deliveries.clear
        perform_enqueued_jobs { post printer_issues_path, params: params }
        mail = ActionMailer::Base.deliveries.last
        expect(mail.to).to eq(["maint@example.com"])
        expect(mail.subject).to eq("New Printer Issue: Bed issue: warped")
      end

      # WART(D-EQ22): the failed-create branch calls `sanitize`, which the controller does not include, so any validation failure is a NoMethodError (500) and the user never sees the error
      it "500s on a blank summary and persists nothing" do
        expect { post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "" } } }.not_to change(PrinterIssue, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "500s on an unknown printer (same failure branch)" do
        expect { post printer_issues_path, params: { printer_issue: { printer_id: 0, summary: "x" } } }.not_to change(PrinterIssue, :count)
        expect(response).to have_http_status(:internal_server_error)
      end

      it "ignores a reporter_id param (reporter is always current_user)" do
        post printer_issues_path, params: { printer_issue: { printer_id: printer.id, summary: "x", reporter_id: 0 } }
        expect(PrinterIssue.last.reporter_id).to eq(staff.id)
      end
    end

    describe "PATCH update (resolution)" do
      it "resolves an issue and redirects to the list" do
        patch printer_issue_path(issue), params: { printer_issue: { active: false } }
        expect(issue.reload.active).to be false
        expect(response).to redirect_to(printer_issues_path)
      end

      it "keeps an active issue's redirect on the issue page" do
        patch printer_issue_path(issue), params: { printer_issue: { description: "More detail" } }
        expect(response).to redirect_to(printer_issue_path(issue))
        expect(issue.reload.description).to eq("More detail")
      end

      it "lets any staff member (not just the reporter) resolve" do
        expect(issue.reporter_id).not_to eq(staff.id)
        patch printer_issue_path(issue), params: { printer_issue: { active: false } }
        expect(issue.reload.active).to be false
      end

      # WART(D-EQ18): a failed update redirects to the list and then redirects again, raising DoubleRenderError (500); the issue is unchanged
      it "500s with a double redirect when the update is invalid" do
        patch printer_issue_path(issue), params: { printer_issue: { summary: "" } }
        expect(response).to have_http_status(:internal_server_error)
        expect(issue.reload.summary).to include("Nozzle clogged")
      end

      # WART(D-EQ19): update permits printer_id, so staff can silently move an issue to another printer
      it "can re-point the issue at a different printer" do
        other = create(:printer, :UM3_01)
        patch printer_issue_path(issue), params: { printer_issue: { printer_id: other.id } }
        expect(issue.reload.printer_id).to eq(other.id)
      end
    end

    describe "DELETE destroy" do
      # WART(D-EQ20): staff DELETE silently redirects to the list without a flash; only admins delete
      it "silently ignores staff" do
        expect { delete printer_issue_path(issue) }.not_to change(PrinterIssue, :count)
        expect(response).to redirect_to(printer_issues_path)
        expect(flash[:alert]).to be_nil
      end
    end

    describe "PATCH update_notification_email" do
      it "stores a valid address, clears a blank one and rejects garbage" do
        patch update_notification_email_printer_issues_path, params: { notification_email: " maint@example.com " }
        expect(response).to redirect_to(printer_issues_path)
        expect(flash[:notice]).to eq("Notification email updated to maint@example.com.")
        expect(Setting.maintenance_email).to eq("maint@example.com")
        patch update_notification_email_printer_issues_path, params: { notification_email: "nope" }
        expect(flash[:alert]).to eq("Invalid email address.")
        expect(Setting.maintenance_email).to eq("maint@example.com")
        patch update_notification_email_printer_issues_path, params: { notification_email: "" }
        expect(flash[:notice]).to eq("Notification email removed.")
        expect(Setting.maintenance_email).to be_blank
      end
    end
  end

  describe "as admin" do
    before { sign_in_as(:admin) }

    it "destroys an issue with a 303 to the list" do
      expect { delete printer_issue_path(issue) }.to change(PrinterIssue, :count).by(-1)
      expect(response).to redirect_to(printer_issues_path)
      expect(response).to have_http_status(:see_other)
    end

    # WART(D-EQ21): destroy uses find_by(...).destroy; an unknown id raises NoMethodError (500)
    it "500s destroying an unknown issue" do
      delete printer_issue_path(0)
      expect(response).to have_http_status(:internal_server_error)
    end
  end
end
