json.extract! pix_transaction, :id, :user_id, :amount, :status, :transaction_type, :pix_key, :description, :created_at, :updated_at
json.url pix_transaction_url(pix_transaction, format: :json)
