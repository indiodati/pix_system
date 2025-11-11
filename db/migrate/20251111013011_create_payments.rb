class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.string :witetec_id
      t.string :external_ref
      t.string :gateway_status
      t.string :payment_method
      t.datetime :paid_at

      t.timestamps
    end
  end
end
