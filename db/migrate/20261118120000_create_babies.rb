# Moves the per-baby profile (name, birthdate, nap count, day window) off
# users into babies so one account can track several babies. Every existing
# user gets one baby built from their current columns, and all of their timer
# runs are attached to it. The old user columns are kept (and ignored by the
# User model) so a rollback or a mid-deploy request doesn't lose data; drop
# them in a later migration.
class CreateBabies < ActiveRecord::Migration[7.2]
  def up
    create_table :babies do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.date :birthdate
      t.integer :daily_nap_count, default: 3, null: false
      t.integer :daily_nap_count_alt
      t.integer :day_start_minutes, default: 570, null: false
      t.integer :day_end_minutes, default: 1320, null: false
      t.timestamps
    end

    add_reference :timer_runs, :baby, foreign_key: true
    add_index :timer_runs, %i[baby_id submitted]
    add_index :timer_runs, %i[baby_id run_type]

    execute <<~SQL
      INSERT INTO babies (user_id, name, birthdate, daily_nap_count, daily_nap_count_alt,
                          day_start_minutes, day_end_minutes, created_at, updated_at)
      SELECT id, baby_name, baby_birthdate, daily_nap_count, daily_nap_count_alt,
             day_start_minutes, day_end_minutes, NOW(), NOW()
      FROM users
    SQL

    execute <<~SQL
      UPDATE timer_runs
      SET baby_id = babies.id
      FROM babies
      WHERE babies.user_id = timer_runs.user_id
    SQL
  end

  def down
    # Copy each user's first baby back onto the user before dropping babies.
    execute <<~SQL
      UPDATE users
      SET baby_name = first_babies.name,
          baby_birthdate = first_babies.birthdate,
          daily_nap_count = first_babies.daily_nap_count,
          daily_nap_count_alt = first_babies.daily_nap_count_alt,
          day_start_minutes = first_babies.day_start_minutes,
          day_end_minutes = first_babies.day_end_minutes
      FROM (
        SELECT DISTINCT ON (user_id) *
        FROM babies
        ORDER BY user_id, created_at, id
      ) AS first_babies
      WHERE first_babies.user_id = users.id
    SQL

    remove_reference :timer_runs, :baby, foreign_key: true, index: true
    drop_table :babies
  end
end
