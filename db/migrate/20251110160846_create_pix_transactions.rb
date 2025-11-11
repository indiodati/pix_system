class CreatePixTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :pix_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :amount
      t.string :status
      t.string :transaction_type
      t.string :pix_key
      t.string :description

      t.timestamps
    end
  end
end
