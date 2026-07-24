class AddEmailVerificationToUsers < ActiveRecord::Migration[7.2]
  def up
    add_column :users, :email_verification_code, :string
    add_column :users, :email_verification_sent_at, :datetime
    add_column :users, :email_verified_at, :datetime

    # Grandfather existing accounts so they are not locked out.
    execute <<-SQL.squish
      UPDATE users
      SET email_verified_at = created_at
      WHERE email_verified_at IS NULL
    SQL
  end

  def down
    remove_column :users, :email_verification_code
    remove_column :users, :email_verification_sent_at
    remove_column :users, :email_verified_at
  end
end
