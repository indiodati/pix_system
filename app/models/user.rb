class User < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable

  has_many :pix_transactions, dependent: :destroy
  has_many :withdrawals,      dependent: :destroy

  validates :email, presence: true, uniqueness: true
  validates :pix_fee_percent, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :withdraw_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # === FORMATAÇÃO DE TAXA E LIMITES ===
  def pix_fee_percent=(value)
    value = value.tr(',', '.') if value.is_a?(String)
    super(value)
  end

  def pix_fee_percent
    super.to_f
  end

  def withdraw_limit=(value)
    value = value.tr(',', '.') if value.is_a?(String)
    super(value)
  end

  def withdraw_limit
    super.to_f
  end

  # === SALDO EM CENTAVOS ===
  def credit!(cents)
    update!(balance_cents: balance_cents.to_i + cents.to_i)
  end

  def debit!(cents)
    raise "Saldo insuficiente" if cents.to_i > balance_cents.to_i
    update!(balance_cents: balance_cents.to_i - cents.to_i)
  end

  def balance_reais
    balance_cents.to_i / 100.0
  end

  # Limite máximo por saque (em centavos)
  def max_withdrawable_cents
    limit_cents = (withdraw_limit.to_f * 100).round
    [balance_cents, limit_cents].min
  end
end
