# app/controllers/santsbank_webhooks_controller.rb
class SantsbankWebhooksController < ApplicationController
  # Webhook vem de fora, então desligamos CSRF
  protect_from_forgery with: :null_session

  # 🔐 Proteções extras
  before_action :verify_source_ip!
  before_action :parse_payload!
  # before_action :verify_token!

  # Lista de IPs permitidos (se vazio, não bloqueia por IP)
  # Exemplo:
  #   SANTS_WEBHOOK_ALLOWED_IPS="18.231.12.34,54.232.98.76"
  ALLOWED_IPS = (ENV["SANTS_WEBHOOK_ALLOWED_IPS"] || "").split(",").map(&:strip).freeze

  def receive
    payload = @payload # já parseado no before_action

    Rails.logger.info "[SANTS WEBHOOK] payload=#{payload.inspect}"

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

  # ==========================================
  # 1) Restrição de IP
  # ==========================================
  def verify_source_ip!
    # Se não tiver nenhum IP configurado, não bloqueia (útil pra dev)
    return if ALLOWED_IPS.blank?

    ip = request.remote_ip

    unless ALLOWED_IPS.include?(ip)
      Rails.logger.warn "[SANTS WEBHOOK] IP não permitido: #{ip} (allowed=#{ALLOWED_IPS.join(',')})"
      head :forbidden
    end
  end

  # ==========================================
  # 2) Parse do payload (JSON ou params)
  # ==========================================
  def parse_payload!
    raw = request.raw_post.to_s.strip

    @payload =
      if raw.present? && request.content_mime_type&.json?
        # JSON "puro" vindo no body
        JSON.parse(raw) rescue {}
      elsif params[:santsbank_webhook].present?
        # Caso venha embrulhado num root params[:santsbank_webhook]
        params[:santsbank_webhook].to_unsafe_h rescue params[:santsbank_webhook].to_h
      else
        # Fallback: pega tudo que veio nos params, menos coisas de Rails
        params.to_unsafe_h.except("controller", "action", "format")
      end

    unless @payload.is_a?(Hash) && @payload.present?
      Rails.logger.warn "[SANTS WEBHOOK] payload inválido ou vazio (raw='#{raw[0..200]}')"
      @payload = {}
    end
  end

  # ==========================================
  # 3) Validação do token (com secure_compare)
  # ==========================================
  def verify_token!
    expected_token = ENV["SANTS_WEBHOOK_TOKEN"].to_s

    # Se não tiver token configurado em env, não bloqueia (mas loga)
    if expected_token.blank?
      Rails.logger.warn "[SANTS WEBHOOK] SANTS_WEBHOOK_TOKEN não configurado. Token não será validado!"
      return
    end

    incoming_token = @payload["token"].to_s

    if incoming_token.blank?
      Rails.logger.warn "[SANTS WEBHOOK] token ausente no payload"
      return render json: { ok: false, error: "missing token" }, status: :unauthorized
    end

    # Comparação segura pra evitar timing attack
    unless ActiveSupport::SecurityUtils.secure_compare(incoming_token, expected_token)
      Rails.logger.warn "[SANTS WEBHOOK] token inválido: #{incoming_token}"
      return render json: { ok: false, error: "invalid token" }, status: :unauthorized
    end
  end

  # ================================
  # PIX OUT (saque via Sants)
  # ================================
  def handle_pix_out(payload)
    status_raw       = payload["status"].to_s        # "Em processamento", "Sucesso", "Erro", "Falha"
    codigo_transacao = payload["codigoTransacao"].to_s
    id_envio         = payload["idEnvio"].to_s
    end_to_end       = payload["endToEndId"].to_s
    valor            = payload["valor"]              # na Sants vem -500 para R$ 5,00
    erro             = payload["erro"]

    # valor em centavos, absoluto (pra exibir bonito nos logs)
    valor_cents = begin
      valor.to_i
    rescue
      0
    end

    valor_cents_abs = valor_cents.abs
    valor_reais     = (valor_cents_abs / 100.0).round(2)

    Rails.logger.info(
      "[SANTS WEBHOOK] PixOut codigoTransacao=#{codigo_transacao} " \
      "idEnvio=#{id_envio} status=#{status_raw} valor=#{valor_cents} (R$ #{'%.2f' % valor_reais}) " \
      "endToEndId=#{end_to_end}"
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

      # COMPLETED pela primeira vez → debita saldo
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

      # FAILED depois de COMPLETED → recredita
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

    if erro.present?
      Rails.logger.warn "[SANTS WEBHOOK] PixOut erro=#{erro.inspect} para codigoTransacao=#{codigo_transacao}"
    end
  rescue => e
    Rails.logger.error "[SANTS WEBHOOK] ERRO handle_pix_out: #{e.class} - #{e.message}"
  end

  # ================================
  # PIX IN
  # ================================
  def handle_pix_in(payload)
    Rails.logger.info "[SANTS WEBHOOK] PixIn recebido payload=#{payload.inspect}"
    # Aqui depois você pode:
    # - localizar conta do recebedor
    # - creditar saldo
    # - registrar PixTransaction etc.
  rescue => e
    Rails.logger.error "[SANTS WEBHOOK] ERRO handle_pix_in: #{e.class} - #{e.message}"
  end
end
