# Puts back the categories of 35 project proposals and the category and equipment of one
# repository that were lost between the production backups of 2026-08-22 and 2026-11-01
# (their rows were removed when the records were edited). The rows are the ones in those
# backups, embedded below: course codes and equipment names only, no user data.
#
# A parent that still exists and still has no categories (respectively no equipment) gets
# its snapshot rows. A parent that has gained rows since, or that no longer exists, is left
# alone, and no existing row is ever updated or deleted. Every inserted row is recorded in
# restored_rows by the statement that inserts it, so down can remove exactly those rows.
# Safe to run again: the parents then have rows, so nothing is inserted.
class RestoreLostCategoriesAndEquipment < ActiveRecord::Migration[8.1]
  ARCHIVE = "restored_rows".freeze
  SOURCE = "20261108000001".freeze

  PARENT_TABLES = { "ProjectProposal" => "project_proposals", "Repository" => "repositories" }.freeze
  PARENT_COLUMNS = { "ProjectProposal" => "project_proposal_id", "Repository" => "repository_id" }.freeze

  # [parent type, parent id, name, category_option_id, created_at, updated_at]
  CATEGORIES = [
    ["ProjectProposal", 581, "GNG2101/GNG2501", nil, "2026-06-04 20:41:03.00948", "2026-06-04 20:41:03.00948"],
    ["ProjectProposal", 582, "GNG2101/GNG2501", nil, "2026-06-02 20:48:06.489966", "2026-06-02 20:48:06.489966"],
    ["ProjectProposal", 583, "GNG2101/GNG2501", nil, "2026-06-02 21:28:43.076261", "2026-06-02 21:28:43.076261"],
    ["ProjectProposal", 584, "GNG2101/GNG2501", nil, "2026-06-26 16:22:09.865817", "2026-06-26 16:22:09.865817"],
    ["ProjectProposal", 585, "GNG2101/GNG2501", nil, "2026-07-07 18:52:03.837088", "2026-07-07 18:52:03.837088"],
    ["ProjectProposal", 587, "GNG2101/GNG2501", nil, "2026-07-27 21:04:44.886766", "2026-07-27 21:04:44.886766"],
    ["ProjectProposal", 588, "GNG2101/GNG2501", nil, "2026-07-24 21:09:00.074309", "2026-07-24 21:09:00.074309"],
    ["ProjectProposal", 590, "GNG2101/GNG2501", nil, "2026-07-27 18:46:08.617515", "2026-07-27 18:46:08.617515"],
    ["ProjectProposal", 591, "GNG2101/GNG2501", nil, "2026-07-28 15:16:11.709187", "2026-07-28 15:16:11.709187"],
    ["ProjectProposal", 592, "GNG2101/GNG2501", nil, "2026-07-27 19:25:16.355931", "2026-07-27 19:25:16.355931"],
    ["ProjectProposal", 593, "GNG2101/GNG2501", nil, "2026-07-27 19:37:08.447947", "2026-07-27 19:37:08.447947"],
    ["ProjectProposal", 594, "GNG2101/GNG2501", nil, "2026-07-27 20:04:35.648746", "2026-07-27 20:04:35.648746"],
    ["ProjectProposal", 595, "GNG2101/GNG2501", nil, "2026-08-11 14:12:45.407841", "2026-08-11 14:12:45.407841"],
    ["ProjectProposal", 596, "GNG2101/GNG2501", nil, "2026-07-27 20:51:02.551689", "2026-07-27 20:51:02.551689"],
    ["ProjectProposal", 597, "GNG1103/GNG1503", nil, "2026-07-28 18:35:01.954446", "2026-07-28 18:35:01.954446"],
    ["ProjectProposal", 598, "GNG1103/GNG1503", nil, "2026-07-28 19:57:00.666753", "2026-07-28 19:57:00.666753"],
    ["ProjectProposal", 599, "GNG2101/GNG2501", nil, "2026-08-04 16:25:11.323433", "2026-08-04 16:25:11.323433"],
    ["ProjectProposal", 600, "GNG2101/GNG2501", nil, "2026-07-30 21:40:23.781195", "2026-07-30 21:40:23.781195"],
    ["ProjectProposal", 601, "GNG2101/GNG2501", nil, "2026-08-11 14:38:56.541479", "2026-08-11 14:38:56.541479"],
    ["ProjectProposal", 602, "GNG2101/GNG2501", nil, "2026-08-11 14:53:09.425456", "2026-08-11 14:53:09.425456"],
    ["ProjectProposal", 603, "GNG2101/GNG2501", nil, "2026-08-16 20:04:08.403939", "2026-08-16 20:04:08.403939"],
    ["ProjectProposal", 604, "GNG2101/GNG2501", nil, "2026-08-17 13:58:28.019013", "2026-08-17 13:58:28.019013"],
    ["ProjectProposal", 605, "GNG2101/GNG2501", nil, "2026-08-16 21:15:48.149203", "2026-08-16 21:15:48.149203"],
    ["ProjectProposal", 606, "GNG2101/GNG2501", nil, "2026-08-16 21:53:58.137558", "2026-08-16 21:53:58.137558"],
    ["ProjectProposal", 607, "GNG2101/GNG2501", nil, "2026-08-16 22:13:21.092842", "2026-08-16 22:13:21.092842"],
    ["ProjectProposal", 608, "GNG2101/GNG2501", nil, "2026-08-17 22:04:25.320631", "2026-08-17 22:04:25.320631"],
    ["ProjectProposal", 609, "GNG2101/GNG2501", nil, "2026-08-16 22:53:12.144214", "2026-08-16 22:53:12.144214"],
    ["ProjectProposal", 610, "GNG1103/GNG1503", nil, "2026-08-17 19:06:06.593549", "2026-08-17 19:06:06.593549"],
    ["ProjectProposal", 611, "GNG2101/GNG2501", nil, "2026-08-17 21:14:06.497742", "2026-08-17 21:14:06.497742"],
    ["ProjectProposal", 612, "GNG2101/GNG2501", nil, "2026-08-18 13:19:49.022182", "2026-08-18 13:19:49.022182"],
    ["ProjectProposal", 613, "GNG2101/GNG2501", nil, "2026-08-18 18:38:26.473916", "2026-08-18 18:38:26.473916"],
    ["ProjectProposal", 614, "GNG2101/GNG2501", nil, "2026-08-18 18:55:04.692389", "2026-08-18 18:55:04.692389"],
    ["ProjectProposal", 615, "GNG2101/GNG2501", nil, "2026-08-18 19:37:26.025428", "2026-08-18 19:37:26.025428"],
    ["ProjectProposal", 616, "GNG2101/GNG2501", nil, "2026-08-18 19:47:07.320162", "2026-08-18 19:47:07.320162"],
    ["ProjectProposal", 617, "GNG2101/GNG2501", nil, "2026-08-19 15:11:25.417624", "2026-08-19 15:11:25.417624"],
    ["Repository", 2132, "GNG1103/GNG1503", nil, "2024-12-04 04:29:52.767104", "2024-12-04 04:29:52.767104"],
  ].freeze

  # [parent type, parent id, name, created_at, updated_at]
  EQUIPMENT = [
    ["Repository", 2132, "iPad", "2024-12-04 04:29:52.770289", "2024-12-04 04:29:52.770289"],
  ].freeze

  def up
    create_archive_table
    counts = Hash.new(0)
    snapshot_groups.each do |table, parent_type, parent_id, rows|
      counts[restore_parent(table, parent_type, parent_id, rows)] += rows.size
    end
    say "restored #{counts[:inserted]} rows; skipped #{counts[:gone]} whose parent no longer exists " \
        "and #{counts[:has_rows]} whose parent has rows now"
  end

  # Removes the archived rows, each only if it still has the parent and name it was inserted
  # with. Raises, changing nothing, unless every archived row matches; the archive is dropped
  # only after the rows are removed.
  def down
    unless table_exists?(ARCHIVE)
      raise "#{ARCHIVE} is missing: this database ran a version of the migration that did not record its changes, " \
            "so they cannot be removed; nothing was changed"
    end

    archived = select_value("SELECT COUNT(*) FROM #{ARCHIVE} WHERE migration_version = '#{SOURCE}'").to_i
    matching = %w[categories equipment].sum { |table| count_unchanged(table) }
    if matching != archived
      raise "Cannot remove the restored rows: #{matching} of #{archived} still match what was inserted " \
            "(the others were changed or removed since); nothing was changed and the archive was kept"
    end

    %w[categories equipment].each { |table| delete_unchanged(table) }
    execute "DROP TABLE #{ARCHIVE}"
  end

  private

  def create_archive_table
    create_table ARCHIVE, if_not_exists: true do |t|
      t.text :migration_version, null: false
      t.text :table_name, null: false
      t.bigint :row_id, null: false
      t.text :parent_type, null: false
      t.bigint :parent_id, null: false
      t.text :name
      t.datetime :archived_at, null: false, default: -> { "now()" }
    end
  end

  # [table, parent type, parent id, rows] for every parent in the snapshot, in a stable order.
  def snapshot_groups
    categories = CATEGORIES.group_by { |row| row[0..1] }.map { |(type, id), rows| ["categories", type, id, rows] }
    equipment = EQUIPMENT.group_by { |row| row[0..1] }.map { |(type, id), rows| ["equipment", type, id, rows] }
    categories + equipment
  end

  # Inserts the rows for one parent and archives them in the same statement, only when the
  # parent exists (locked until commit) and has no rows of that kind. Returns :inserted,
  # :gone (no such parent) or :has_rows.
  def restore_parent(table, parent_type, parent_id, rows)
    inserted = execute(insert_sql(table, parent_type, parent_id, rows)).cmd_tuples
    return :inserted if inserted.positive?

    select_value("SELECT 1 FROM #{PARENT_TABLES.fetch(parent_type)} WHERE id = #{parent_id.to_i}") ? :has_rows : :gone
  end

  def insert_sql(table, parent_type, parent_id, rows)
    column = PARENT_COLUMNS.fetch(parent_type)
    <<~SQL.squish
      WITH parent AS (SELECT id FROM #{PARENT_TABLES.fetch(parent_type)} WHERE id = #{parent_id.to_i} FOR UPDATE),
      inserted AS (
        INSERT INTO #{table} (#{column}, #{table == 'categories' ? 'name, category_option_id' : 'name'}, created_at, updated_at)
        SELECT parent.id, v.* FROM parent, (VALUES #{values_sql(table, rows)}) AS v
        WHERE NOT EXISTS (SELECT 1 FROM #{table} existing WHERE existing.#{column} = parent.id)
        RETURNING id, #{column} AS parent_id, name
      )
      INSERT INTO #{ARCHIVE} (migration_version, table_name, row_id, parent_type, parent_id, name)
      SELECT '#{SOURCE}', '#{table}', id, #{connection.quote(parent_type)}, parent_id, name FROM inserted
    SQL
  end

  def values_sql(table, rows)
    rows.map { |_type, _id, name, *rest| "(#{value_sql(table, name, rest)})" }.join(", ")
  end

  # Categories carry category_option_id before the timestamps; equipment does not.
  def value_sql(table, name, rest)
    option, created, updated = table == "categories" ? rest : [nil, *rest]
    parts = [connection.quote(name) + "::varchar"]
    parts << "#{option ? option.to_i : 'NULL'}::integer" if table == "categories"
    parts << "#{connection.quote(created)}::timestamp"
    parts << "#{connection.quote(updated)}::timestamp"
    parts.join(", ")
  end

  def unchanged_rows_sql(table)
    <<~SQL.squish
      FROM #{ARCHIVE} a JOIN #{table} t ON t.id = a.row_id
      WHERE a.migration_version = '#{SOURCE}' AND a.table_name = '#{table}'
        AND a.name IS NOT DISTINCT FROM t.name
        AND a.parent_id = CASE a.parent_type WHEN 'ProjectProposal' THEN #{project_proposal_expr(table)} ELSE t.repository_id END
    SQL
  end

  def project_proposal_expr(table)
    table == "categories" ? "t.project_proposal_id" : "NULL"
  end

  def count_unchanged(table)
    select_value("SELECT COUNT(*) #{unchanged_rows_sql(table)}").to_i
  end

  def delete_unchanged(table)
    execute "DELETE FROM #{table} WHERE id IN (SELECT t.id #{unchanged_rows_sql(table)})"
  end
end
