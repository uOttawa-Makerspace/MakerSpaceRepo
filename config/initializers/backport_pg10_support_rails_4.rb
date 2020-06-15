# frozen_string_literal: true

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module SchemaStatements
        # Resets the sequence of a table's primary key to the maximum value.
        def reset_pk_sequence!(table, pk = nil, sequence = nil) #:nodoc:
          unless pk && sequence
            default_pk, default_sequence = pk_and_sequence_for(table)

            pk ||= default_pk
            sequence ||= default_sequence
          end

          @logger.warn "#{table} has primary key #{pk} with no default sequence" if @logger && pk && !sequence

          if pk && sequence
            quoted_sequence = quote_table_name(sequence)
            max_pk = select_value("SELECT MAX(#{quote_column_name pk}) FROM #{quote_table_name(table)}")
            if max_pk.nil?
              minvalue = if postgresql_version >= 100_000
                           select_value("SELECT seqmin FROM pg_sequence WHERE seqrelid = #{quote(quoted_sequence)}::regclass")
                         else
                           select_value("SELECT min_value FROM #{quoted_sequence}")
                         end
            end

            select_value <<-end_sql, 'SCHEMA'
              SELECT setval(#{quote(quoted_sequence)}, #{max_pk || minvalue}, #{max_pk ? true : false})
            end_sql
          end
        end
      end
    end
  end
end
