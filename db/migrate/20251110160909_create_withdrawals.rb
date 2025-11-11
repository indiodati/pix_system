class CreateWithdrawals < ActiveRecord::Migration[7.1]
  def change
    create_table :withdrawals do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount
      t.string :status
      t.string :pix_key

      t.timestamps
    end
  end
end
