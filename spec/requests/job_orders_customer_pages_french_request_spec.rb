# frozen_string_literal: true

require "rails_helper"

# The job order pages a customer sees (pay, quote approval and its confirmation, invoice, order list, order page,
# wizard steps) and the task messages follow the chosen language, amounts and dates included. Names entered by
# staff (job types, services, options) and task titles are data and stay as entered. Page text is squished, so a
# French no-break space reads as a plain space there.
RSpec.describe "Job order customer pages in English and French", type: :request do
  let(:owner) { create(:user, :regular_user, name: "Owner Person") }
  let(:staff) { create(:user, :staff) }
  let(:fr) { { locale: "fr" } }

  before do
    stub_shopify_admin!.invoice_url = "https://pay.example/invoice"
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  around { |example| travel_to(Time.zone.local(2026, 11, 13, 14, 30)) { example.run } }

  def page_text = Nokogiri::HTML(response.body).text.squish

  def quoted_order!(status_key)
    order = make_job_order!(owner: owner, status_key: status_key)
    order.job_tasks.create!(title: "Task #1").build_job_task_quote(price: 1234.5, service_price: 0, service_quantity: 0).save!
    order.reload
  end

  def typed_task!(order, title, type: "3D Print")
    order.job_tasks.create!(title: title, job_type: JobType.find_by!(name: type))
  end

  describe "pay page" do
    it "is in English" do
      get pay_job_orders_path, params: { token: quoted_order!(:completed).pay_token }

      expect(page_text).to include(
        "Thank You for ordering a Job Order!", "You can now pay for your order!", "We do not save any payment information",
        "Total Quote: $1,234.50", "Proceed to the payment page", "Having trouble or have any questions? Contact Us!",
        "makerspace@uottawa.ca (For General Questions and Administrative issues)",
        "uottawa.makerepo@gmail.com (Website Technical Issues)"
      )
    end

    it "is in French, with a French amount" do
      get pay_job_orders_path, params: { token: quoted_order!(:completed).pay_token }.merge(fr)

      expect(page_text).to include(
        "Merci d'avoir passé une commande!", "Vous pouvez maintenant payer votre commande!",
        "Nous ne conservons aucune information de paiement", "Total du devis : 1 234,50 $",
        "Passer à la page de paiement", "Vous éprouvez des difficultés ou avez des questions? Écrivez-nous!",
        "makerspace@uottawa.ca (questions générales et administratives)",
        "uottawa.makerepo@gmail.com (problèmes techniques du site Web)"
      )
      expect(page_text).not_to include("Thank You", "Total Quote", "Contact Us")
      expect(response.body).to include("1\u00A0234,50\u00A0$", 'href="mailto:makerspace@uottawa.ca"', 'href="https://pay.example/invoice"')
    end
  end

  describe "quote approval page and its confirmation" do
    it "is in English" do
      order = quoted_order!(:user_approval)
      get user_magic_approval_job_orders_path, params: { token: order.approval_token }

      expect(page_text).to include("Thank You for ordering a Job Order!", "You can Accept or Deny your quote on this page!",
                                   "Total Quote: $1,234.50", "Approve the Quote", "Deny the Quote", "Contact Us!")

      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "true" }

      expect(page_text).to include("Thank You for Approving/Denying the Job Order!", "Contact Us!")
    end

    it "is in French" do
      order = quoted_order!(:user_approval)
      get user_magic_approval_job_orders_path, params: { token: order.approval_token }.merge(fr)

      expect(page_text).to include("Vous pouvez accepter ou refuser votre devis sur cette page!",
                                   "Total du devis : 1 234,50 $", "Approuver le devis", "Refuser le devis")
      expect(page_text).not_to include("Approve the Quote", "Deny the Quote")

      patch user_magic_approval_confirmation_job_orders_path, params: { token: order.approval_token, approved: "true" }.merge(fr)

      expect(page_text).to include("Merci d'avoir approuvé ou refusé la commande!", "Écrivez-nous!")
      expect(page_text).not_to include("Thank You")
    end
  end

  describe "invoice" do
    let(:order) do
      order = add_quoted_tasks!(make_job_order!(owner: owner, status_key: :paid))
      group = create(:job_service_group, name: "Materials", job_type: JobType.find_by!(name: "3D Print"))
      service = create(:job_service, name: "PLA", unit: "g", job_service_group: group)
      order.job_tasks.find_by!(title: "Print A").update!(job_type: group.job_type, job_service: service)
      order.job_tasks.create!(title: "Print D").build_job_task_quote(price: 0, service_price: 2, service_quantity: 1.5).save!
      order.job_quote_line_items.create!(description: "x", price: 4).update_column(:description, "") # rubocop:disable Rails/SkipsModelValidations
      order.reload
    end

    before { session_login!(owner) }

    it "is in English" do
      get job_order_invoice_path(order)

      expect(response.body).to include("<title>Job Order Invoice</title>", "Invoice ##{order.id}", "Client : Owner Person",
                                       "Date : 2026/11/13", "Print this page")
      expect(page_text).to include(
        "University Of Ottawa Richard L'Abbé Makerspace STM 107 150 Louis Pasteur Ottawa, ON K1N 6N5", "Payment Method",
        "Please see https://en.wiki.makerepo.com/wiki/How_to_pay_for_an_Order for payment details", "Item Price",
        "Print A - Base Fee CAD $20.00", "Print A - PLA (Materials) - 4.0 g CAD $12.00", "Print A - Polish (Option) CAD $7.25",
        "Print D - Service - 1.5 unit CAD $3.00", "Line Item CAD $4.00", "Total: CAD $65.50"
      )
    end

    it "is in French, with French amounts, quantities and date" do
      get job_order_invoice_path(order), params: fr

      expect(response.body).to include('<html lang="fr">', "<title>Facture de la commande</title>", "Imprimer cette page")
      expect(page_text).to include(
        "Facture n° #{order.id}", "Makerspace Richard-L'Abbé de l'Université d'Ottawa STM 107 150, rue Louis-Pasteur",
        "Ottawa (Ontario) K1N 6N5", "Client : Owner Person", "Date : 13/11/2026", "Mode de paiement",
        "Consultez https://en.wiki.makerepo.com/wiki/How_to_pay_for_an_Order pour les détails du paiement", "Article Prix",
        "Print A - Frais de base 20,00 $ CA", "Print A - PLA (Materials) - 4,0 g 12,00 $ CA",
        "Print A - Polish (option) 7,25 $ CA", "Print D - Service - 1,5 unité 3,00 $ CA", "Article 4,00 $ CA",
        "Total : 65,50 $ CA"
      )
      expect(page_text).not_to include("Invoice #", "Base Fee", "CAD", "Payment Method")
    end

    # A deleted account is hidden from every user lookup, so the order has no customer to name.
    it "names a deleted customer in each language" do
      order
      owner.soft_delete!
      session_login!(staff)

      get job_order_invoice_path(order)
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Client : [DELETED USER]", "Total: CAD $65.50")

      get job_order_invoice_path(order), params: fr
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Client : [UTILISATEUR SUPPRIMÉ]", "Total : 65,50 $ CA")
    end

    it "names a customer whose account is gone in each language" do
      order.update_column(:user_id, nil) # rubocop:disable Rails/SkipsModelValidations
      session_login!(staff)

      get job_order_invoice_path(order)
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Client : [DELETED USER]")

      get job_order_invoice_path(order), params: fr
      expect(response).to have_http_status(:ok)
      expect(page_text).to include("Client : [UTILISATEUR SUPPRIMÉ]")
    end
  end

  describe "order list" do
    before do
      session_login!(owner)
      JobStatus.where(name: JobStatus::STATUS_NAMES[:staff_approval]).update_all(name_fr: "En attente d'approbation du personnel") # rubocop:disable Rails/SkipsModelValidations
      JobStatus.reset_lookup_cache!
      order = make_job_order!(owner: owner, status_key: :staff_approval)
      typed_task!(order, "Task #1")
      ChatMessage.create!(job_order: order, sender: staff, message: "hello")
    end

    it "is in English" do
      get job_orders_path

      expect(page_text).to include("Chats User ID Submitted Type Status View", "1 unread messages",
                                   "November 13, 2026 14:30", "Waiting for Staff Approval")
    end

    it "is in French, with the status in French" do
      get job_orders_path, params: fr

      expect(page_text).to include("Messages Utilisateur N° Soumise le Type Statut Voir", "1 messages non lus",
                                   "13 novembre 2026 à 14:30", "En attente d'approbation du personnel")
      expect(page_text).not_to include("Chats", "Submitted", "unread messages", "Waiting for Staff Approval")
    end
  end

  describe "order page" do
    let(:order) do
      order = make_job_order!(owner: owner, status_key: :draft)
      typed_task!(order, "Task #1").user_files.attach(io: StringIO.new("solid"), filename: "part.stl")
      typed_task!(order, "Task #2")
      order
    end

    it "is in English for the owner" do
      session_login!(owner)
      get job_order_path(order)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("form button, form input[type=submit]").map { |b| b.text.presence || b["value"] }).to include("Delete")
      expect(doc.css("a[title]").map { |a| a["title"] }).to include("Download")
      expect(page_text).to include("Tasks", "Client Files", "Add Another Task")
    end

    it "is in French for the owner" do
      session_login!(owner)
      get job_order_path(order), params: fr

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("form button, form input[type=submit]").map { |b| b.text.presence || b["value"] }).to include("Supprimer")
      expect(doc.css("a[title]").map { |a| a["title"] }).to include("Télécharger")
      expect(doc.css("a[title]").map { |a| a["title"] }).not_to include("Download")
      expect(page_text).to include("Tâches", "Fichiers du client", "Ajouter une Autre Tâche")
    end

    it "names a deleted customer in each language" do
      order.update_column(:user_id, nil) # rubocop:disable Rails/SkipsModelValidations
      session_login!(staff)

      get job_order_path(order)
      expect(page_text).to include("[DELETED USER]")

      get job_order_path(order), params: fr
      expect(page_text).to include("[UTILISATEUR SUPPRIMÉ]")
      expect(page_text).not_to include("[DELETED USER]")
    end
  end

  describe "wizard" do
    let(:order) { make_job_order!(owner: owner, status_key: :draft) }
    let(:job_type) { JobType.find_by!(name: "3D Print").tap { |type| type.update!(service_fee: 1234.5) } }
    let(:task) do
      group = create(:job_service_group, name: "Materials", job_type: job_type)
      create(:job_service, name: "PLA", unit: "g", internal_price: 10, external_price: 15.5, job_service_group: group)
      typed_task!(order, "Task #1")
    end

    before { session_login!(owner) }

    it "shows the service step in English" do
      get edit_job_order_job_task_path(order, task, step: 2)

      expect(page_text).to include("Add Another File", "Fees", "Service Fee $1,234.50", "PLA ($15.5/g)")
    end

    it "shows the service step in French" do
      get edit_job_order_job_task_path(order, task, step: 2), params: fr

      expect(page_text).to include("Ajouter un autre fichier", "Frais", "Frais de service 1 234,50 $", "PLA (15,5 $/g)")
      expect(page_text).not_to include("Add Another File", "Fees")
    end

    it "titles the design request step in each language" do
      design = typed_task!(order, "Task #2", type: "Design Services")

      get edit_job_order_job_task_path(order, design, step: 2)
      expect(page_text).to include("Create Job Order", "Add Another File")

      get edit_job_order_job_task_path(order, design, step: 2), params: fr
      expect(page_text).to include("Créer une commande", "Ajouter un autre fichier")
      expect(page_text).not_to include("Create Job Order")
    end

    it "shows the last step in each language" do
      get edit_job_order_job_task_path(order, task, step: 4)
      expect(page_text).to include("Add Another Task", "Save Draft")

      get edit_job_order_job_task_path(order, task, step: 4), params: fr
      expect(page_text).to include("Ajouter une Autre Tâche", "Enregistrer le Brouillon")
      expect(page_text).not_to include("Save Draft")
    end
  end

  describe "job order menu" do
    it "names the staff and admin links in each language" do
      session_login!(create(:user, :admin))

      get landing_job_orders_path
      expect(page_text).to include("All Job Orders (Staff Only)", "Settings (Admin Only)")

      get landing_job_orders_path, params: fr
      expect(page_text).to include("Toutes les commandes (personnel seulement)", "Paramètres (administrateurs seulement)")
      expect(page_text).not_to include("Staff Only", "Admin Only")
    end
  end

  describe "task messages" do
    let(:order) { make_job_order!(owner: owner, status_key: :draft).tap { |o| typed_task!(o, "Task #1") } }

    before { session_login!(owner) }

    it "says a task was deleted in each language" do
      delete job_order_job_task_path(order, typed_task!(order, "Task #2"))
      expect(flash[:notice]).to eq("Task was successfully deleted.")

      delete job_order_job_task_path(order, typed_task!(order, "Task #3")), params: fr
      expect(flash[:notice]).to eq("La tâche a été supprimée.")
    end

    it "says a task could not be created in each language" do
      order
      invalid = JobTask.new.tap { |task| task.errors.add(:base, "Broken") }
      allow_any_instance_of(JobTask).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid)) # rubocop:disable RSpec/AnyInstance

      post job_order_job_tasks_path(order)
      expect(flash[:alert]).to eq("Failed to create task: Broken")

      post job_order_job_tasks_path(order), params: fr
      expect(flash[:alert]).to eq("La tâche n'a pas pu être créée : Broken")
    end
  end
end
