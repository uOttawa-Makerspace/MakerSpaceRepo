# frozen_string_literal: true

require "rails_helper"

# Refusals raised by models for volunteer tasks and hours, coupons and booking access requests read in the
# language of the request: English as it always did, French text for French users.
RSpec.describe "Localized refusal messages" do
  def in_locale(locale, &block) = I18n.with_locale(locale, &block)

  describe CouponCode do
    it "explains a refused deletion of a claimed coupon" do
      coupon = create(:coupon_code, :claimed, user: create(:user))
      en = in_locale(:en) { coupon.destroy && nil; coupon.errors[:base] }
      fr = in_locale(:fr) { coupon.errors.clear; coupon.destroy; coupon.errors[:base] }
      expect(en).to eq(["A user has already claimed this coupon with CCs, so it cannot be deleted"])
      expect(fr).to eq(["Un utilisateur a déjà réclamé ce coupon avec des CC, il ne peut donc pas être supprimé"])
    end
  end

  describe VolunteerTask do
    let(:task) { create(:volunteer_task) }
    let(:by) { create(:user, :admin) }

    it "explains a refused deletion of an awarded task" do
      create(:volunteer_hour, :approved1, volunteer_task: task)
      fr = in_locale(:fr) { task.destroy; task.errors[:base] }
      expect(fr).to eq(["Cette tâche a des heures approuvées ou des CC attribués et ne peut pas être supprimée."])
    end

    it "explains a refused edit of the people and trainings on the task" do
      expectations = {
        { add_staff: [0] } => ["The staff to add could not be found.", "Le membre du personnel à ajouter est introuvable."],
        { add_volunteers: [0] } => ["The volunteer to add could not be found.", "Le bénévole à ajouter est introuvable."],
        { remove_volunteers: [0] } => ["The volunteer to remove is not on this task.", "Le bénévole à retirer n'est pas sur cette tâche."]
      }
      expectations.each do |joins, (english, french)|
        expect(edit_errors(:en, joins: joins)).to eq([english])
        expect(edit_errors(:fr, joins: joins)).to eq([french])
      end
    end

    it "explains a refused edit that names a missing training" do
      expect(edit_errors(:en, certification_ids: [0])).to eq(["A required training does not exist."])
      expect(edit_errors(:fr, certification_ids: [0])).to eq(["Une formation requise n'existe pas."])
    end

    it "explains a refused removal of the last staff member and of a user who is not on the task" do
      creator = create(:user, :staff)
      task.update!(user: creator)
      create(:volunteer_task_join, :active, volunteer_task: task, user: creator)
      expect(remove_errors(:en, creator.id)).to eq(["There must be at least one staff member assigned to this task."])
      expect(remove_errors(:fr, creator.id)).to eq(["Au moins un membre du personnel doit être assigné à cette tâche."])
      expect(remove_errors(:fr, 0)).to eq(["L'utilisateur à retirer n'est pas sur cette tâche."])
    end

    def edit_errors(locale, joins: {}, certification_ids: [])
      in_locale(locale) do
        fresh = VolunteerTask.find(task.id)
        fresh.update_from_form({}, by: by, joins: joins, certification_ids: certification_ids)
        fresh.errors[:base]
      end
    end

    def remove_errors(locale, user_id)
      in_locale(locale) do
        fresh = VolunteerTask.find(task.id)
        fresh.remove_user(user_id, by: by)
        fresh.errors[:base]
      end
    end
  end

  describe VolunteerHour do
    it "explains a date in the future" do
      task = create(:volunteer_task)
      refusal = lambda do |locale|
        in_locale(locale) do
          hour = VolunteerHour.new(user: create(:user))
          hour.save_hand_logged(volunteer_task_id: task.id, date_of_task: Date.current + 1, total_time: 2)
          hour.errors[:date_of_task]
        end
      end
      expect(refusal.call(:en)).to eq(["cannot be in the future"])
      expect(refusal.call(:fr)).to eq(["ne peut pas être dans le futur"])
    end
  end

  describe UserBookingApproval do
    let(:user) { create(:user, :regular_user) }
    let(:admin) { create(:user, :admin) }

    def refusal(locale, from, to)
      request = UserBookingApproval.create!(user: user, identity: "Other", comments: "x", date: Date.current)
      request.update_columns(status: from)
      request.status = to
      in_locale(locale) { request.valid?; request.errors[:base] }
    end

    {
      "pending" => ["This request was already pending.", "Cette demande est déjà en attente."],
      "approved" => ["This request was already approved.", "Cette demande a déjà été approuvée."],
      "declined" => ["This request was already declined.", "Cette demande a déjà été refusée."],
      "revoked" => ["This request was already revoked.", "Cette demande a déjà été révoquée."]
    }.each do |from, (english, french)|
      it "says the request was already #{from}" do
        to = from == "pending" ? "revoked" : "pending"
        expect(refusal(:en, from, to)).to eq([english])
        expect(refusal(:fr, from, to)).to eq([french])
      end
    end

    it "says the account that sent the request has been deleted" do
      request = UserBookingApproval.create!(user: user, identity: "Other", comments: "x", date: Date.current)
      user.update_column(:deleted, true)
      request.status = "approved"
      expect(in_locale(:en) { request.valid?; request.errors[:base] }).to include("The account that sent this request has been deleted.")
      expect(in_locale(:fr) { request.valid?; request.errors[:base] }).to include("Le compte qui a envoyé cette demande a été supprimé.")
    end

    it "refuses a second request with the reason, in each language" do
      UserBookingApproval.create!(user: user, identity: "Other", comments: "x", date: Date.current)
      expect(in_locale(:en) { user.request_booking_access(comments: "y", identity: "Other").errors[:base] })
        .to eq(["You have already requested access."])
      expect(in_locale(:fr) { user.request_booking_access(comments: "y", identity: "Other").errors[:base] })
        .to eq(["Vous avez déjà demandé l'accès."])
    end

    it "tells a user who has access that they already have it, in each language" do
      user.update!(booking_approval: true) if user.respond_to?(:booking_approval=)
      allow(user).to receive(:booking_approval?).and_return(true)
      expect(in_locale(:en) { user.request_booking_access(comments: "y", identity: "Other").errors[:base] })
        .to eq(["You already have booking access."])
      expect(in_locale(:fr) { user.request_booking_access(comments: "y", identity: "Other").errors[:base] })
        .to eq(["Vous avez déjà accès aux réservations."])
    end
  end
end
