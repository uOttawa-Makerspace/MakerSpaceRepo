class AddIndexToUsersForUsernameAndName < ActiveRecord::Migration[6.1]
  def up
    execute("CREATE OR REPLACE FUNCTION public.immutable_unaccent(regdictionary, text)
                  RETURNS text LANGUAGE c IMMUTABLE PARALLEL SAFE STRICT AS
                '$libdir/unaccent', 'unaccent_dict';

                CREATE OR REPLACE FUNCTION public.f_unaccent(text)
                  RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT AS
                $func$
                SELECT public.immutable_unaccent(regdictionary 'public.unaccent', $1)
                $func$;"
    )

    add_index :users, 'LOWER(f_unaccent(name)) varchar_pattern_ops', name: 'index_users_name_lower'
    add_index :users, 'LOWER(f_unaccent(username)) varchar_pattern_ops', name: 'index_users_username_lower'
    add_index :users, 'LOWER(f_unaccent(email)) varchar_pattern_ops', name: 'index_users_email_lower'
  end

  def down
    remove_index :users, name: 'index_users_name_lower'
    remove_index :users, name: 'index_users_username_lower'
    remove_index :users, name: 'index_users_email_lower'

    execute('drop function f_unaccent;')
    execute('drop function immutable_unaccent;')
  end
end
