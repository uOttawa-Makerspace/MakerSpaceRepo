# frozen_string_literal: true

require "rails_helper"

# The printer pages list every printer (with its model, active issues and latest session). Their
# queries must not grow with the number of printers or printer models.
RSpec.describe "Printer pages queries", :aggregate_failures, type: :request do
  let(:reporter) { create(:user, :regular_user) }

  # Each call adds one printer model with one printer that has an active and a closed issue and a
  # session, so every per-printer and per-model read on the pages has a row to read.
  def add_printers(count)
    Array.new(count) do
      type = create(:printer_type, :Random)
      printer = create(:printer, number: "01", printer_type: type)
      create(:printer_issue, :nozzle_clogged, printer: printer, reporter: reporter)
      create(:printer_issue, :bed_issue, :inactive, printer: printer, reporter: create(:user, :regular_user))
      create(:printer_session, printer: printer, user: create(:user, :regular_user))
      printer
    end
  end

  def summary_hints
    JSON.parse(CGI.unescapeHTML(response.body[/issueSummary = (\{.*?\})\s*</m, 1]))
  end

  def queries_with(count, path)
    add_printers(count)
    get path # warm caches
    count_queries { get path }
  end

  def doc
    Nokogiri::HTML(response.body)
  end

  context "as staff" do
    before { sign_in_as(:staff) }

    it "gives the new-issue form every printer with its active-issue counts in a constant number of queries" do
      few = queries_with(1, new_printer_issue_path)
      many = queries_with(3, new_printer_issue_path)
      expect(many).to eq(few)

      printers = Printer.with_type.to_a
      expect(doc.css("#printer_issue_printer_id option").map(&:text).drop(1)).to eq(printers.map(&:name))
      expect(summary_hints).to eq(printers.to_h { |p| [p.id.to_s, { "Nozzle clogged" => 1 }] })
    end

    it "leaves the edited issue out of the counts on the edit form in a constant number of queries" do
      first = add_printers(1).first
      edited = first.printer_issues.find_by(active: true)
      path = edit_printer_issue_path(edited)
      get path
      few = count_queries { get path }
      add_printers(3)
      many = count_queries { get path }
      expect(many).to eq(few)

      expect(summary_hints.keys).to match_array(Printer.where.not(id: first.id).map { |p| p.id.to_s })
      expect(doc.css("#printer_issue_printer_id option[selected]").map(&:text)).to eq([first.name])
    end

    it "lists every issue with its printer and reporter in a constant number of queries" do
      few = queries_with(1, printer_issues_path)
      many = queries_with(3, printer_issues_path)
      expect(many).to eq(few)

      tables = doc.css("table.table tbody")
      active, closed = PrinterIssue.order(:printer_id).partition(&:active)
      expect(tables[0].css("tr").map { |tr| tr.css("td")[1].text }).to eq(active.map { |i| i.printer.name })
      expect(tables[1].css("tr").map { |tr| tr.css("td")[4].text }).to eq(closed.map { |i| i.reporter.name })
      expect(doc.css("ul.list-unstyled li").map(&:text)).to eq(active.map { |i| i.printer.name })
    end

    it "shows each model's last assignment on the assign page in a constant number of queries" do
      few = queries_with(1, staff_printers_printers_path)
      many = queries_with(3, staff_printers_printers_path)
      expect(many).to eq(few)

      PrinterType.find_each do |type|
        last = type.printer_sessions.order(created_at: :desc).first
        expect(response.body).to include(
          "Last Update: Printer Number: #{last.printer.number} | User: #{last.user.username.capitalize}"
        )
      end
    end

    it "shows the last assignment of a model across its printers, and none for a model without sessions" do
      type = create(:printer_type, :Random)
      older = create(:printer, number: "01", printer_type: type)
      newer = create(:printer, number: "02", printer_type: type)
      unused = create(:printer, number: "01", printer_type: create(:printer_type, :Random))
      create(:printer_session, printer: newer, created_at: 2.days.ago)
      latest = create(:printer_session, printer: older, created_at: 1.day.ago)

      get staff_printers_printers_path

      sections = doc.css("h2").to_h { |h2| [h2.text, h2.parent.text.squish] }
      expect(sections[type.name]).to include(
        "Last Update: Printer Number: 01 | User: #{latest.user.username.capitalize}"
      )
      expect(sections[unused.printer_type.name]).not_to include("Last Update")
    end
  end

  context "as admin" do
    before { sign_in_as(:admin) }

    it "lists every printer with its model in the remove form in a constant number of queries" do
      few = queries_with(1, printers_path)
      many = queries_with(3, printers_path)
      expect(many).to eq(few)

      labels = doc.css("#remove_printer option").map(&:text).drop(1)
      expect(labels).to eq(Printer.with_type.map(&:model_and_number))
    end
  end
end
