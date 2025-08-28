class CreateMembershipTiersAndUpdateMemberships < ActiveRecord::Migration[7.2]
  def change
    create_table :membership_tiers do |t|
      t.string  :title_en, null: false
      t.string  :title_fr, null: false
      t.integer :duration, null: false
      t.decimal :internal_price, precision: 8, scale: 2, null: false, default: 0
      t.decimal :external_price, precision: 8, scale: 2, null: false, default: 0
      t.boolean :hidden, default: false, null: false

      t.timestamps
    end

    add_reference :memberships, :membership_tier, foreign_key: true, index: true

    reversible do |dir|
      dir.up do
        tiers = {
          '1_day' => {
            duration: 1.day,
            internal_price: 2,
            external_price: 4,
            title_en: '1 Day Membership',
            title_fr: 'Adhésion 1 jour'
          },
          '1_month' => {
            duration: 1.month,
            internal_price: 6,
            external_price: 12,
            title_en: '1 Month Membership',
            title_fr: 'Adhésion 1 mois'
          },
          '1_semester' => {
            duration: 4.months,
            internal_price: 25,
            external_price: 50,
            title_en: '1 Semester Membership',
            title_fr: 'Adhésion 1 semestre'
          },
          'custom' => {
            duration: 1.hour,
            internal_price: 0,
            external_price: 0,
            title_en: 'Custom Membership',
            title_fr: 'Adhésion Personnalisée',
            hidden: true
          },
          'faculty' => {
            duration: 4.months,
            internal_price: 100,
            external_price: 100,
            title_en: 'Faculty membership',
            title_fr: 'Adhésion de la faculté',
            hidden: true
          }
        }

        tier_ids = {}
        tiers.each do |key, attrs|
          record = execute <<~SQL
            INSERT INTO membership_tiers (title_en, title_fr, duration, internal_price, external_price, hidden, created_at, updated_at)
            VALUES (
              #{ActiveRecord::Base.connection.quote(attrs[:title_en])},
              #{ActiveRecord::Base.connection.quote(attrs[:title_fr])},
              #{attrs[:duration].to_i},
              #{attrs[:internal_price]},
              #{attrs[:external_price]},
              #{attrs[:hidden] ? 'TRUE' : 'FALSE'},
              CURRENT_TIMESTAMP,
              CURRENT_TIMESTAMP
            )
            RETURNING id
          SQL
          tier_ids[key] = record.first['id']
        end

        execute <<~SQL
          UPDATE memberships SET membership_tier_id = #{tier_ids['1_day']} WHERE membership_type = '1_day';
          UPDATE memberships SET membership_tier_id = #{tier_ids['1_month']} WHERE membership_type = '1_month';
          UPDATE memberships SET membership_tier_id = #{tier_ids['1_semester']} WHERE membership_type = '1_semester';
          UPDATE memberships SET membership_tier_id = #{tier_ids['custom']} WHERE membership_type = 'custom';
          UPDATE memberships SET membership_tier_id = #{tier_ids['faculty']} WHERE membership_type = 'faculty';
        SQL
      end
    end

    remove_column :memberships, :membership_type, :string
  end
end
