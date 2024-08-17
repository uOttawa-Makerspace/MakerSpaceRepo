require "rails_helper"

RSpec.describe PrinterIssuesController, type: :controller do
  before(:each) do
    @printer = create(:printer, :UM2P_01)
    @staff = create :user, :staff
    session[:user_id] = @staff.id
    session[:expires_at] = Time.zone.now + 10_000
  end

  describe "GET CRUD pages" do
    context "logged in as staff" do
      it "should return 200 ok for all" do
        get :index
        expect(response).to have_http_status(:success)
        get :new
        expect(response).to have_http_status(:success)
        issue = create :printer_issue
        get :show, params: { id: issue.id }
        expect(response).to have_http_status(:success)
        get :edit, params: { id: issue.id }
        expect(response).to have_http_status(:success)
      end
    end

    context "logged in as regular user" do
      it "should redirect index to home page" do
        user = create :user, :regular_user
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end
  end

  describe "POST /printer_issues" do
    context "create new issue as regular user" do
      it "should deny access" do
        user = create :user, :regular_user
        session[:user_id] = user.id
        post :index,
             params: {
               printer_id: @printer.id,
               summary: "Issue summary lol",
               description: ""
             }
        expect(response).to redirect_to root_path
      end
    end

    context "As staff" do
      it "should create new issue" do
        # Get new page, post new issue, and show issue
        get :new
        expect(response).to have_http_status(:success)

        expect {
          post :create,
               params: {
                 printer_issue: {
                   printer_id: @printer.id,
                   summary: "Issue summary lol",
                   description: ""
                 }
               }
          print flash[:alert]
        }.to change(PrinterIssue, :count).by 1

        issue = PrinterIssue.last
        get :show, params: { id: issue.id }
        expect(response).to have_http_status(:success)
        get :index
        expect(response).to have_http_status(:success)
      end

      it "should close and re-open issue" do
        issue = create :printer_issue
        expect(issue.active).to be true
        patch :update, params: { id: issue, printer_issue: { active: "false" } }
        issue.reload
        expect(flash[:alert]).to be nil
        expect(response).to redirect_to printer_issues_path
        expect(issue.active).to be false
      end

      it "should group issues correctly" do
        # Very fragile test, I don't like it
        create :printer_issue
        create :printer_issue
        create :printer_issue
        # for each premade summary
        PrinterIssue.summaries.values.each do |summary|
          # create two issues
          create :printer_issue, summary: summary
          create :printer_issue, summary: summary
        end
        # get issue summary
        get :index
        issues_summary = assigns(:issues_summary)
        # test we have two in each category
        PrinterIssue.summaries.values.each do |summary|
          expect(issues_summary[summary].count).to be 2
        end
        # Other category
        expect(issues_summary["Other"].count).to be 3
      end

      it "should prevent deleting issues" do
        delete :destroy, params: { id: create(:printer_issue) }
        expect(response).to redirect_to printer_issues_path
      end
    end

    context "As admin" do
      it "should allow deleting posts" do
        admin = create :user, :admin
        session[:user_id] = admin.id
        issue = create :printer_issue
        expect(PrinterIssue.count).to be(1)
        expect { delete :destroy, params: { id: issue.id } }.to change(
          PrinterIssue,
          :count
        ).by(-1)
        expect(PrinterIssue.count).to be 0
      end
    end
  end
end
