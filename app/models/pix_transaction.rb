class PixTransaction < ApplicationRecord
  belongs_to :user

  # Campo virtual usado só no form (valor em reais tipo "10,00")
  attr_accessor :amount_reais

  # Qual provedor gerou esse PIX
  enum gateway: {
    witetec:  0,
    santsbank: 1
  }, _default: :witetec

  # ===== VALIDATIONS =====

  validates :amount, presence: true

  # ID da transação no gateway (Witetec ou Sants)
  validates :gateway_id, presence: true, uniqueness: true

  validates :fee_amount,
            numericality: { greater_than_or_equal_to: 0 }

  # ===== SCOPES =====

  scope :paid_pix, -> {
    where(transaction_type: "PIX")
      .where("LOWER(status) = ?", "paid")
  }

  # ===== HELPERS =====

  def net_amount_cents
    amount.to_i - fee_amount.to_i
  end
end
