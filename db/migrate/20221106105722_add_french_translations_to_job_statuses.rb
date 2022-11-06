class AddFrenchTranslationsToJobStatuses < ActiveRecord::Migration[6.1]
  def change
    add_column :job_statuses, :name_fr, :string
    add_column :job_statuses, :description_fr, :string

    reversible do |change|
      change.up do
        JobStatus.find_by(name: "Draft").update(
          name_fr: "Brouillon",
          description_fr:
            "Le travail est un brouillon et n'a pas encore été envoyé pour approbation."
        )

        JobStatus.find_by(name: "Waiting for Staff Approval").update(
          name_fr: "En attente de l'approbation du personnel",
          description_fr:
            "La commande a été envoyée pour approbation par le personnel"
        )

        JobStatus.find_by(name: "Waiting for User Approval").update(
          name_fr: "En attente de l'approbation du client",
          description_fr:
            "Nous attendons actuellement votre approbation de la commande"
        )

        JobStatus.find_by(name: "Sent a Quote Reminder").update(
          name_fr: "Envoi d'un rappel de devis",
          description_fr:
            "En attendant que l'utilisateur approuve la commande, un rappel de devis a été envoyé."
        )

        JobStatus.find_by(name: "Waiting to be Processed").update(
          name_fr: "En attente de traitement",
          description_fr:
            "En attente du traitement de la commande ou de son envoi à la fabrication."
        )

        JobStatus.find_by(name: "Currently being Processed").update(
          name_fr: "Actuellement en cours de traitement",
          description_fr: "La commande est en cours de traitement."
        )

        JobStatus.find_by(name: "Completed").update(
          name_fr: "Completé",
          description_fr:
            "La commande est achevée. Vous pouvez maintenant procéder au paiement."
        )

        JobStatus.find_by(name: "Paid").update(
          name_fr: "Payé",
          description_fr: "Le client a payé pour la commande."
        )

        JobStatus.find_by(name: "Picked-Up").update(
          name_fr: "Ramassé",
          description_fr: "Le client a ramassé la commande."
        )

        JobStatus.find_by(name: "Declined").update(
          name_fr: "Refusé",
          description_fr:
            "La commande a été annulée par le client ou le personnel."
        )
      end
    end
  end
end
