class Withdrawal < ApplicationRecord
  belongs_to :user

  validates :pix_key, presence: true
  validates :amount, presence: true,
                     numericality: { only_integer: true, greater_than: 0 }

  # ✅ Essas regras SÓ fazem sentido na criação do saque.
  validate :user_must_have_enough_balance,    on: :create
  validate :amount_cannot_exceed_user_limit, on: :create

  after_create :debit_user_balance!

  def amount_reais
    amount.to_i / 100.0
  end

  private

  def user_must_have_enough_balance
    return if user.blank? || amount.blank?

    if amount.to_i > user.balance_cents.to_i
      errors.add(
        :amount,
        "não pode ser maior que seu saldo disponível (R$ #{format('%.2f', user.balance_reais)})"
      )
    end
  end

  def amount_cannot_exceed_user_limit
    return if user.blank? || amount.blank?

    # ⚠️ Se não tiver limite configurado ou for <= 0, não bloqueia
    return if user.withdraw_limit.blank? || user.withdraw_limit.to_f <= 0

    limit_cents = (user.withdraw_limit.to_f * 100).round
    if amount.to_i > limit_cents
      errors.add(
        :amount,
        "não pode ser maior que o limite de saque por operação (R$ #{format('%.2f', user.withdraw_limit)})"
      )
    end
  end

  def debit_user_balance!
    user.debit!(amount)
  rescue => e
    Rails.logger.error "Erro ao debitar saldo: #{e.class} - #{e.message}"
  end
end
