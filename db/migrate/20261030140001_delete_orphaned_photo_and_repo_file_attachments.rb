# MovePhotosToProjectProposal (20260328190305) re-attached each Photo#image /
# RepoFile#file blob to its ProjectProposal and then delete_all'd the Photo /
# RepoFile rows, leaving the original active_storage_attachments rows pointing
# at records that no longer exist. Remove only those: attachment rows whose
# record is gone AND whose blob is still attached to a ProjectProposal. Blobs
# and stored files are never touched, and an orphan whose blob is not on a
# proposal is left alone. Idempotent.
class DeleteOrphanedPhotoAndRepoFileAttachments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      DELETE FROM active_storage_attachments a
      WHERE ((a.record_type = 'Photo' AND a.name = 'image'
              AND NOT EXISTS (SELECT 1 FROM photos p WHERE p.id = a.record_id))
          OR (a.record_type = 'RepoFile' AND a.name = 'file'
              AND NOT EXISTS (SELECT 1 FROM repo_files r WHERE r.id = a.record_id)))
        AND EXISTS (SELECT 1 FROM active_storage_attachments pp
                    WHERE pp.blob_id = a.blob_id AND pp.record_type = 'ProjectProposal')
    SQL
  end

  def down
    # Irreversible by design: the removed rows pointed at deleted records.
  end
end
