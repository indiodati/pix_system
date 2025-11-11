# app/controllers/witetec_webhooks_controller.rb
class WitetecWebhooksController < ApplicationController
  # Webhook vem de fora, então desligamos CSRF
  protect_from_forgery with: :null_session

  def receive
    payload_raw = request.raw_post.presence || "{}"
    payload     = JSON.parse(payload_raw) rescue {}
    Rails.logger.info("[WITETEC WEBHOOK] payload=#{payload.inspect}")

    event_type = payload["eventType"].to_s

    case
    when event_type.start_with?("TRANSACTION_")
      handle_transaction_webhook(payload)
    when event_type.start_with?("WITHDRAWAL_")
      handle_withdrawal_webhook(payload)
    else
      Rails.logger.warn("[WITETEC WEBHOOK] eventType desconhecido: #{event_type}")
    end

    render json: { ok: true, eventType: event_type }
  rescue => e
    Rails.logger.error("[WITETEC WEBHOOK] ERRO receive: #{e.class} - #{e.message}")
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  # ===================================
  # TRANSAÇÃO (PIX / cartão / boleto)
  # ===================================
  def handle_transaction_webhook(payload)
    status       = payload["status"].to_s.upcase      # "PAID", "PENDING", "FAILED", etc
    witetec_id   = payload["id"].to_s                 # id da transação na Witetec
    method       = payload["method"].to_s             # "PIX", "CREDIT_CARD", etc
    external_ref = payload.dig("items", 0, "externalRef")

    Rails.logger.info(
      "[WITETEC WEBHOOK] TRANSACTION #{witetec_id} " \
      "status=#{status} method=#{method} externalRef=#{external_ref}"
    )

    # ----- LOG DE GATEWAY: Payment -----
    payment = Payment.find_or_initialize_by(witetec_id: witetec_id)
    payment.external_ref    ||= external_ref
    payment.gateway_status    = status.downcase        # "paid", "pending", "failed"
    payment.payment_method    = method
    payment.paid_at         ||= Time.current if status == "PAID"
    payment.save!

    # ----- NEGÓCIO: PixTransaction -----
    pix_tx = PixTransaction.find_by(witetec_id: witetec_id)

    unless pix_tx
      Rails.logger.warn("[WITETEC WEBHOOK] PixTransaction não encontrada para witetec_id=#{witetec_id}")
      return
    end

    prev_status = pix_tx.status.to_s.upcase

    PixTransaction.transaction do
      pix_tx.transaction_type = method if pix_tx.respond_to?(:transaction_type=)
      pix_tx.status           = status
      pix_tx.save!

      # Crédito só quando muda para PAID e ainda não era pago
      if status == "PAID" && prev_status != "PAID"
        valor = pix_tx.net_amount_cents # <= valor já com taxa descontada
        pix_tx.user.credit!(valor)
        Rails.logger.info("[WITETEC WEBHOOK] Crédito PIX: user_id=#{pix_tx.user_id} +#{valor} cents")
      end

      # (Opcional) se quiser estornar quando vier FAILED após já ter sido PAID:
      # if status == "FAILED" && prev_status == "PAID"
      #   valor = pix_tx.net_amount_cents
      #   pix_tx.user.debit!(valor)
      #   Rails.logger.info("[WITETEC WEBHOOK] Estorno PIX: user_id=#{pix_tx.user_id} -#{valor} cents")
      # end
    end
  rescue => e
    Rails.logger.error("[WITETEC WEBHOOK] ERRO handle_transaction_webhook: #{e.class} - #{e.message}")
  end

  # ===================================
  # SAQUE / WITHDRAWAL
  # ===================================
  def handle_withdrawal_webhook(payload)
    status       = payload["status"].to_s.upcase
    witetec_id   = payload["id"].to_s
    method       = payload["method"].to_s
    external_ref = payload["externalRef"]

    Rails.logger.info(
      "[WITETEC WEBHOOK] WITHDRAWAL #{witetec_id} " \
      "status=#{status} method=#{method} externalRef=#{external_ref}"
    )

    # LOG de gateway
    cash_out = CashOut.find_or_initialize_by(witetec_id: witetec_id)
    cash_out.external_ref   ||= external_ref
    cash_out.gateway_status   = status.downcase
    cash_out.method           = method
    cash_out.paid_at        ||= Time.current if status == "PAID"
    cash_out.save!

    # NEGÓCIO: Withdrawal existente
    withdrawal = Withdrawal.find_by(witetec_id: witetec_id)

    unless withdrawal
      Rails.logger.warn("[WITETEC WEBHOOK] Withdrawal não encontrado para witetec_id=#{witetec_id}")
      return
    end

    prev_status = withdrawal.status.to_s.upcase

    Withdrawal.transaction do
      # NÃO passa por validações nem callbacks
      withdrawal.update_columns(
        status:     status,
        updated_at: Time.current
      )

      if status == "FAILED" && prev_status != "FAILED"
        user  = withdrawal.user
        valor = withdrawal.amount.to_i
        user.credit!(valor)
        Rails.logger.info("[WITETEC WEBHOOK] Saque FAILED, devolvido #{valor} cents para user_id=#{user.id}")
      end
      # Se for PAID: só mantemos status como PAID e saldo já foi debitado na criação
    end
  rescue => e
    Rails.logger.error("[WITETEC WEBHOOK] ERRO handle_withdrawal_webhook: #{e.class} - #{e.message}")
  end
end
