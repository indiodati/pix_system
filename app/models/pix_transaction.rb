class PixTransaction < ApplicationRecord
  belongs_to :user

  attr_accessor :amount_reais

  validates :amount,     presence: true
  validates :witetec_id, presence: true, uniqueness: true
  validates :fee_amount, numericality: { greater_than_or_equal_to: 0 }

  scope :paid_pix, -> { where(transaction_type: "PIX").where("LOWER(status) = ?", "paid") }

  def net_amount_cents
    amount.to_i - fee_amount.to_i
  end
end
