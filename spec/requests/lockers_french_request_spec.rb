# frozen_string_literal: true

require "rails_helper"

# The locker pages and their messages follow the chosen language, dates included. The JSON
# answers and the Shopify product data shown on the pages are not translated.
RSpec.describe "Locker pages in French", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:owner) { create(:user, :regular_user, username: "owneruser") }
  let(:student) { create(:user, :student, username: "studentuser") }
  let(:size) { create(:locker_size, size: "16x16", shopify_gid: "gid://shopify/ProductVariant/1") }
  let(:fr) { { locale: "fr" } }

  around { |example| travel_to(Time.zone.local(2026, 11, 13, 14, 30)) { example.run } }

  before do
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  def log_in!(user)
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
  end

  def page_text = Nokogiri::HTML(response.body).text.squish

  describe "lockers admin" do
    before { log_in!(admin) }

    it "shows the locker dashboard and inventory in French, with French dates" do
      LockerOption.lockers_enabled = true
      locker = create(:locker, specifier: "101", locker_size: size)
      create(:locker_rental, :active, locker: locker, rented_by: owner, owned_until: Time.zone.local(2026, 12, 3, 12))

      get lockers_path, params: fr

      expect(page_text).to include(
        "Gestion des casiers", "Les nouvelles locations de casiers sont activées.", "Inventaire des casiers",
        "Créer une plage de casiers", "Modifier les casiers actuels", "Taille et UGS", "Loué par", "3 déc.",
        "13 nov. 14:30", "Valide", "Actuellement lié à aucun produit", "Aucun lien valide n'est assigné..."
      )
      expect(page_text).not_to include("Locker Management", "Locker Inventory", "Inline editing", "Indefinite")
    end

    it "shows the store product details in French around the product data" do
      variant = { title: "Small", sku: "S1", id: "gid://shopify/ProductVariant/1", price: "10.00", displayName: "Lockers - Small", image: nil }
      allow(LockerOption).to receive(:locker_product_info).and_return(
        { title: "Lockers", status: "ACTIVE", id: "gid://shopify/Product/1", price: "10.00", image: nil, variants: { variant[:id] => variant } }
      )
      size

      get lockers_path, params: fr

      expect(page_text).to include("Produit principal", "Prix reçu 10.00 $ CA", "Variante de produit de la Makerstore",
                                   "Titre Small", "Lié à : 16x16", "Tailles de casiers", "Lockers - Small")
    end

    it "names a locker without a size by its id" do
      locker = create(:locker, specifier: "101", locker_size: size)
      unnamed = create(:locker_size)
      unnamed.update_column(:size, "")

      get lockers_path, params: fr

      expect(Nokogiri::HTML(response.body).css("select[data-locker-size-for='#{locker.id}'] option").map(&:text))
        .to include("Taille n° #{unnamed.id}")
    end

    it "shows a locker's history in French" do
      locker = create(:locker, specifier: "101", locker_size: size)
      create(:locker_rental, :active, locker: locker, rented_by: owner)

      get locker_path(locker), params: fr

      expect(page_text).to include("Casier 101", "Statut actuel", "loué par owneruser depuis le 13 novembre 2026",
                                   "Historique des locations", "Conception GNG", "active")
      expect(page_text).not_to include("Rental History", "rented by")
    end

    it "gives the locker messages in French" do
      post lockers_path, params: { locker: { specifier: "201", locker_size_id: size.id } }.merge(fr)
      expect(flash[:notice]).to eq("Casier n° 201 créé")

      post create_multiple_lockers_path, params: { range_start: "300", range_end: "301", locker_size_id: size.id }.merge(fr)
      expect(flash[:notice]).to eq("Casiers créés")

      locker = Locker.find_by!(specifier: "201")
      patch locker_path(locker), params: { locker: { notes: "x" } }.merge(fr)
      expect(flash[:notice]).to eq("Casier mis à jour")

      patch bulk_edit_lockers_path, params: { id: [locker.id], locker: { notes: "y" } }.merge(fr)
      expect(flash[:notice]).to eq("Casiers mis à jour")

      patch bulk_edit_lockers_path, params: { id: [Locker.find_by!(specifier: "300").id], bulk_delete: "1", locker: { notes: "" } }.merge(fr)
      expect(flash[:notice]).to eq("Casiers sélectionnés supprimés")

      delete locker_path(locker), params: fr
      expect(flash[:notice]).to eq("Casier supprimé")
    end
  end

  describe "locker rentals" do
    before { CourseName.find_or_create_by!(name: "GNG1103") }

    it "shows the request form in French, with the request types and price" do
      LockerOption.lockers_enabled = true
      allow(LockerOption).to receive(:locker_product_info)
        .and_return({ variants: { size.shopify_gid => { price: "25.00" } } })
      create(:locker, specifier: "105", locker_size: size)
      log_in!(student)

      get new_locker_rental_path, params: fr

      expect(page_text).to include("Nombre disponible", "25.00 $ par session", "Je suis", "Étudiant en GNG",
                                   "Demande générale", "À quel cours êtes-vous inscrit?", "Remarques sur la demande :")
      expect(page_text).not_to include("GNG student", "General request", "per semester")
    end

    it "names the pending request in French with a French date" do
      LockerOption.lockers_enabled = true
      create(:locker_rental, rented_by: owner)
      log_in!(owner)

      get new_locker_rental_path, params: fr

      expect(page_text).to include("Vous avez une demande de casier en attente, soumise le 13/11/2026.",
                                   "Voir la demande de casier actuelle")
    end

    it "says in French that requests are closed" do
      log_in!(owner)

      get new_locker_rental_path, params: fr

      expect(page_text).to include("Les demandes de casiers ne sont pas acceptées pour le moment.")
    end

    it "shows a rental to staff in French, with French dates and staff actions" do
      rental = create(:locker_rental, :active, :student, :with_section_information, rented_by: student,
                                               locker: create(:locker, specifier: "110", locker_size: size),
                                               owned_until: Time.zone.local(2026, 12, 3, 9, 15), paid_at: Time.zone.local(2026, 11, 2, 10))
      create(:locker_payment, locker_rental: rental, paid_at: Time.zone.local(2026, 11, 2, 10))
      log_in!(staff)

      get locker_rental_path(rental), params: fr

      expect(page_text).to include("Demandé en tant que Étudiant", "Casier 110", "3 décembre 2026 à 09:15",
                                   "Payé le 2 novembre 2026 à 10:00", "Location expire le 3 décembre 2026",
                                   "Actions du personnel", "Déplacer le casier", "Terminer la location",
                                   "Remarques internes du personnel", "Inventaire des casiers")
      expect(page_text).not_to include("Staff Actions", "Move Locker", "Student")
    end

    it "shows the renter's own pages in French" do
      create(:locker_rental, :active, rented_by: owner, locker: create(:locker, specifier: "101", locker_size: size),
                                      owned_until: Time.zone.local(2026, 12, 3, 12))
      log_in!(owner)

      get locker_rentals_path, params: fr
      expect(page_text).to include("Consultez ici l'historique de vos locations de casiers", "Jusqu'au 3 décembre 2026",
                                   "Casiers du CEED", "Demander un casier", "Mon historique de casiers", "Général")

      get user_path(owner.username), params: fr
      expect(page_text).to include("Possédée jusqu'à 3 décembre 2026 à 12:00")
    end

    it "shows the staff lists in French" do
      create(:locker_rental, :active, rented_by: owner, locker: create(:locker, specifier: "110", locker_size: size),
                                      owned_until: Time.zone.local(2026, 11, 10, 12))
      log_in!(staff)

      get admin_locker_rentals_path, params: fr
      expect(page_text).to include("Locations de casiers", "Aucune demande en attente.", "Locations actives", "Expiré")

      get expired_locker_rentals_path, params: fr
      expect(page_text).to include("Locations de casiers expirées", "Expirée le 10 novembre 2026, il y a 3 jours")

      log_in!(admin)
      get assign_locker_locker_rentals_path, params: fr
      expect(page_text).to include("Assigner un casier à un utilisateur", "Indéterminée (sans expiration)")
    end

    it "gives the rental messages in French" do
      locker = create(:locker, specifier: "101", locker_size: size)
      allow_any_instance_of(LockerRental).to receive(:sync_shopify_draft_order_after_commit).and_return(true)
      log_in!(staff)

      post locker_rentals_path, params: { locker_rental: { rented_by_id: owner.id, locker_id: locker.id, state: "active", requested_as: "staff" } }.merge(fr)
      expect(flash[:notice]).to eq("Casier assigné")

      rental = LockerRental.find_by!(rented_by: owner)
      patch locker_rental_path(rental), params: { locker_rental: { staff_notes: "z" } }.merge(fr)
      expect(flash[:notice]).to eq("Location de casier mise à jour")

      rental.update!(owned_until: 2.days.ago)
      patch renew_locker_rental_path(rental), params: fr
      expect(flash[:notice]).to eq("Renouvellement du casier commencé. Veuillez effectuer le paiement pour renouveler votre casier.")
    end
  end
end
