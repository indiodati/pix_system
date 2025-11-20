class SantsbankWebhooksController < ApplicationController
  protect_from_forgery with: :null_session

  def receive
    payload_raw = request.raw_post.presence || "{}"
    payload     = JSON.parse(payload_raw) rescue {}

    Rails.logger.info "[SANTS WEBHOOK] payload=#{payload.inspect}"

    incoming_token = payload["token"].to_s
    expected_token = ENV["SANTS_WEBHOOK_TOKEN"].to_s

    if expected_token.present? && incoming_token != expected_token
      Rails.logger.warn "[SANTS WEBHOOK] token inválido: #{incoming_token}"
      return render json: { ok: false, error: "invalid token" }, status: :unauthorized
    end

    evento = payload["evento"].to_s

    case evento
    when "PixOut"
      handle_pix_out(payload)
    when "PixIn"
      handle_pix_in(payload)
    else
      Rails.logger.warn "[SANTS WEBHOOK] evento desconhecido: #{evento}"
    end

    render json: { ok: true }
  rescue => e
    Rails.logger.error "[SANTS WEBHOOK] ERRO receive: #{e.class} - #{e.message}"
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  private

  def handle_pix_out(payload)
    status_raw        = payload["status"].to_s
    codigo_transacao  = payload["codigoTransacao"].to_s
    id_envio          = payload["idEnvio"].to_s
    end_to_end        = payload["endToEndId"].to_s
    valor             = payload["valor"]
    erro              = payload["erro"]

    Rails.logger.info(
      "[SANTS WEBHOOK] PixOut codigoTransacao=#{codigo_transacao} " \
      "idEnvio=#{id_envio} status=#{status_raw} valor=#{valor} endToEndId=#{end_to_end}"
    )

    withdrawal = Withdrawal.find_by(gateway_id: codigo_transacao)

    unless withdrawal
      Rails.logger.warn "[SANTS WEBHOOK] Withdrawal não encontrado para codigoTransacao=#{codigo_transacao}"
      return
    end

    prev_status = withdrawal.status.to_s.upcase
    user        = withdrawal.user

    normalized_status =
      case status_raw
      when "Sucesso"
        "COMPLETED"
      when "Em processamento"
        "PROCESSING"
      when "Erro", "Falha"
        "FAILED"
      else
        status_raw.to_s.upcase
      end

    Withdrawal.transaction do
      withdrawal.update_columns(
        status:     normalized_status,
        updated_at: Time.current
      )

      if normalized_status == "COMPLETED" && prev_status != "COMPLETED"
        valor_debito = withdrawal.amount.to_i

        begin
          user.debit!(valor_debito)
          Rails.logger.info(
            "[SANTS WEBHOOK] Débito de saque: user_id=#{user.id} -#{valor_debito} cents " \
            "(withdrawal_id=#{withdrawal.id})"
          )
        rescue => e
          Rails.logger.error(
            "[SANTS WEBHOOK] ERRO ao debitar saldo (withdrawal_id=#{withdrawal.id}): " \
            "#{e.class} - #{e.message}"
          )
        end
      end

      if normalized_status == "FAILED" && prev_status == "COMPLETED"
        valor_estorno = withdrawal.amount.to_i

        begin
          user.credit!(valor_estorno)
          Rails.logger.info(
            "[SANTS WEBHOOK] Estorno de saque (rollback): user_id=#{user.id} +#{valor_estorno} cents " \
            "(withdrawal_id=#{withdrawal.id})"
          )
        rescue => e
          Rails.logger.error(
            "[SANTS WEBHOOK] ERRO ao estornar saldo (withdrawal_id=#{withdrawal.id}): " \
            "#{e.class} - #{e.message}"
          )
        end
      end
    end

    Rails.logger.warn "[SANTS WEBHOOK] PixOut erro=#{erro.inspect} para codigoTransacao=#{codigo_transacao}" if erro.present?
  rescue => e
    Rails.logger.error "[SANTS WEBHOOK] ERRO handle_pix_out: #{e.class} - #{e.message}"
  end

  def handle_pix_in(payload)
    Rails.logger.info "[SANTS WEBHOOK] PixIn recebido (ainda não tratado) payload=#{payload.inspect}"
  rescue => e
    Rails.logger.error "[SANTS WEBHOOK] ERRO handle_pix_in: #{e.class} - #{e.message}"
  end
end
