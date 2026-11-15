# frozen_string_literal: true

# db/schema.rb does not record PostgreSQL functions or triggers, so a database built from it (test databases,
# a fresh setup) would lack them. This writes every function and trigger the app defined in the public schema
# (not those of extensions, not the internal ones behind foreign keys) at the end of schema.rb, as SQL that
# loading the schema runs again.
module SchemaDumperTriggers
  FUNCTIONS = <<~SQL.squish
    SELECT pg_get_functiondef(p.oid) FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
    ORDER BY p.proname
  SQL

  TRIGGERS = <<~SQL.squish
    SELECT pg_get_triggerdef(t.oid) FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal
    ORDER BY c.relname, t.tgname
  SQL

  def trailer(stream)
    (@connection.select_values(FUNCTIONS) + @connection.select_values(TRIGGERS)).each do |sql|
      stream.puts
      stream.puts "  execute <<~'SQL'"
      stream.puts sql.strip.gsub(/^(?=.)/, "    ")
      stream.puts "  SQL"
    end
    super
  end
end

ActiveSupport.on_load(:active_record) { ActiveRecord::SchemaDumper.prepend(SchemaDumperTriggers) }
