json.extract! withdrawal, :id, :user_id, :amount, :status, :pix_key, :created_at, :updated_at
json.url withdrawal_url(withdrawal, format: :json)
