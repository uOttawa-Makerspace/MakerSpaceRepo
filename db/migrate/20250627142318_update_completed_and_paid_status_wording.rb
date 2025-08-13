class UpdateCompletedAndPaidStatusWording < ActiveRecord::Migration[7.2]
  def change
    reversible do |change|
      change.up do
        # Update English wording
        JobStatus.find_by(name: "Completed").update(
          name: "Completed (Waiting for Payment)",
          description: "The job has been completed and is waiting for payment."
        )
        
        JobStatus.find_by(name: "Paid").update(
          name: "Paid (Waiting for Pick-Up)",
          description: "The client has paid for the job and it's waiting to be picked up."
        )
        
        # Update French wording
        JobStatus.find_by(name_fr: "Completé").update(
          name_fr: "Completé (En attente de paiement)",
          description_fr: "La commande est achevée et en attente de paiement."
        )
        
        JobStatus.find_by(name_fr: "Payé").update(
          name_fr: "Payé (En attente de ramassage)",
          description_fr: "Le client a payé pour la commande et elle attend d'être ramassée."
        )
      end
      
      change.down do
        # Revert English wording
        JobStatus.find_by(name: "Completed (Waiting for Payment)").update(
          name: "Completed",
          description: "The job has been completed. You can now proceed with your payment."
        )
        
        JobStatus.find_by(name: "Paid (Waiting for Pick-Up)").update(
          name: "Paid",
          description: "The client has paid for the job."
        )
        
        # Revert French wording
        JobStatus.find_by(name_fr: "Completé (En attente de paiement)").update(
          name_fr: "Completé",
          description_fr: "La commande est achevée. Vous pouvez maintenant procéder au paiement."
        )
        
        JobStatus.find_by(name_fr: "Payé (En attente de ramassage)").update(
          name_fr: "Payé",
          description_fr: "Le client a payé pour la commande."
        )
      end
    end
  end
end