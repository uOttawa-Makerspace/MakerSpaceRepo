# frozen_string_literal: true

require "rails_helper"

# The quote modal on a job order's page (staff only) follows the staff member's language. Names entered by staff
# (job types, services, units, options) stay as entered; a service without a unit falls back to the word "unit".
RSpec.describe "Job order quote modal in English and French", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }
  let(:job_type) { JobType.find_by!(name: "3D Print") }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    group = create(:job_service_group, job_type: job_type, name: "Materials")
    with_unit = create(:job_service, job_service_group: group, name: "PLA", unit: "gram")
    without_unit = create(:job_service, job_service_group: group, name: "Resin", unit: nil)
    task = order.job_tasks.create!(title: "Print A", job_type: job_type, job_service: with_unit)
    task.job_task_options.create!(job_option: JobOption.create!(name: "Polish", fee: 2))
    order.job_tasks.create!(title: "Print B", job_type: job_type, job_service: without_unit)
    session_login!(staff)
  end

  def modal = Nokogiri::HTML(response.body).at_css("#quote-modal-rendered")

  def labels = modal.css("label").map { |label| label.text.squish }

  def placeholders = modal.css("input[placeholder]").map { |input| input["placeholder"] }.uniq

  def other_text
    [modal.css(".card-header h5").last.text.squish, modal.at_css("#new-line-item").text.squish,
     modal.at_css("#quote-total").text.squish, modal.at_css("input[type=submit]")["value"]]
  end

  it "is in English" do
    get job_order_path(order)

    expect(labels).to eq(["Base Fee (CAD)", "Number of gram", "Price per gram (CAD)", "Polish (CAD)",
                          "Staff Files (GCode, PDF, etc.)", "Base Fee (CAD)", "Number of unit", "Price per unit (CAD)",
                          "Staff Files (GCode, PDF, etc.)", "Comments for the user (will send as a chat)",
                          "Comments for the staff members"])
    expect(placeholders).to eq(["value", "Description", "0.00", "I will need to add supports", "Use the Raise 3D"])
    expect(other_text).to eq(["Additional Line Items", "New Line Item", "Total: $0.00", "Approve"])
  end

  it "is in French" do
    get job_order_path(order, locale: "fr")

    expect(labels).to eq(["Frais de base ($ CA)", "Quantité (gram)", "Prix par gram ($ CA)", "Polish ($ CA)",
                          "Fichiers du personnel (GCode, PDF, etc.)", "Frais de base ($ CA)", "Quantité (unité)",
                          "Prix par unité ($ CA)", "Fichiers du personnel (GCode, PDF, etc.)",
                          "Commentaires pour l'utilisateur (envoyés dans le clavardage)",
                          "Commentaires pour les membres du personnel"])
    expect(placeholders).to eq(["valeur", "Description", "0.00", "Je devrai ajouter des supports", "Utiliser la Raise 3D"])
    expect(other_text).to eq(["Articles supplémentaires", "Nouvel article", "Total : 0,00 $ CA", "Approuver"])
  end
end
