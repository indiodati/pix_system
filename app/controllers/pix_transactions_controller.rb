# app/controllers/pix_transactions_controller.rb
class PixTransactionsController < ApplicationController
  before_action :authenticate_user!

  # ============================================================
  # INDEX
  # ============================================================
  def index
    @pix_transactions = current_user.pix_transactions
                                    .order(created_at: :desc)
                                    .page(params[:page])
                                    .per(10)
  end

  # ============================================================
  # NEW
  # ============================================================
  def new
    @pix_transaction = PixTransaction.new
  end

  # ============================================================
  # CREATE
  # ============================================================
  def create
    permitted        = pix_transaction_params
    raw_amount_reais = permitted[:amount_reais]
    amount_cents     = parse_amount_to_cents(raw_amount_reais)

    external_ref = "user_#{current_user.id}_tx_#{SecureRandom.hex(4)}"

    # ------------------------------------------------------------
    # Gateway vem do USER agora
    # ------------------------------------------------------------
    gateway =
      if current_user.respond_to?(:effective_pix_gateway)
        current_user.effective_pix_gateway
      else
        current_user.pix_gateway rescue "witetec"
      end

    # segurança extra
    gateway = "witetec" unless %w[witetec santsbank].include?(gateway)

    Rails.logger.info "[PIX CREATE] user_id=#{current_user.id} gateway=#{gateway}"

    # ------------------------------------------------------------
    # Instancia PixTransaction já com gateway
    # ------------------------------------------------------------
    @pix_transaction = current_user.pix_transactions.new(
      description:      permitted[:description],
      amount:           amount_cents,
      transaction_type: "PIX",
      status:           "PENDING",
      external_id:      external_ref,
      gateway:          gateway
    )

    # mantém o valor digitado no form caso dê erro
    @pix_transaction.amount_reais = raw_amount_reais

    # se valor for inválido / zero, já volta pro form
    if amount_cents <= 0
      @pix_transaction.errors.add(:amount_reais, "deve ser maior que zero")
      flash.now[:alert] = "Informe um valor válido para o PIX."
      return render :new
    end

    # ------------------------------------------------------------
    # Service certo
    # ------------------------------------------------------------
    pix_service =
      if gateway == "santsbank"
        SantsPixService.new
      else
        PixService.new
      end

    # ------------------------------------------------------------
    # Chamada ao provider
    # ------------------------------------------------------------
    response =
      if gateway == "santsbank"
        # Sants: valor em CENTAVOS
        pix_service.create_transaction(
          amount:             amount_cents,
          expiration_seconds: 600,
          info:               permitted[:description]
        )
      else
        # Witetec: como já estava
        pix_service.create_transaction(
          amount:            amount_cents,
          customer_name:     current_user.email.split("@").first,
          customer_email:    current_user.email,
          customer_phone:    current_user.phone.presence    || "1234567890",
          customer_document: current_user.document.presence || "00000000000",
          items: [
            {
              title:       @pix_transaction.description.presence || "Pagamento",
              amount:      amount_cents,
              quantity:    1,
              tangible:    true,
              externalRef: external_ref
            }
          ]
        )
      end

    Rails.logger.info "[PIX CREATE] raw response (#{gateway}) => #{response.inspect}"

    # ------------------------------------------------------------
    # Resposta
    # ------------------------------------------------------------
    if response["status"] == true
      data     = response["data"] || {}
      pix_data = data["pix"]      || {}

      Rails.logger.warn "[PIX CREATE] → Gateway=#{gateway} → Data=#{data.inspect}"

      gateway_amount = data["amount"].to_i
      gateway_amount = amount_cents if gateway_amount.zero?

      gateway_fee = data["feeAmount"].to_i if data.key?("feeAmount")

      fee_percent = current_user.pix_fee_percent.to_f
      fee_cents =
        if gateway_fee
          gateway_fee
        else
          ((gateway_amount * fee_percent) / 100.0).round
        end

      @pix_transaction.gateway_id = data["id"]
      @pix_transaction.amount     = gateway_amount
      @pix_transaction.fee_amount = fee_cents
      @pix_transaction.status     = data["status"] || "PENDING"
      @pix_transaction.pix_key    = pix_data["copyPaste"]

      @pix_transaction.save!

      @pix_qrcode_base64 = pix_data["qrcode"]
      @pix_copy_paste    = pix_data["copyPaste"]

      render :show
    else
      http_status = response["http_status"]
      error_msg   = response["error"] ||
                    response["message"] ||
                    response["mensagem"] ||
                    response.inspect

      flash_message = "Erro ao criar PIX (#{gateway}"
      flash_message += " - HTTP #{http_status}" if http_status.present?
      flash_message += "): #{error_msg}"

      flash.now[:alert] = flash_message
      @pix_transaction.errors.add(:base, error_msg)

      render :new
    end

  rescue => e
    Rails.logger.error "[PixTransactionsController] ERRO: #{e.class} - #{e.message}"
    flash.now[:alert] = "Erro interno ao criar PIX."

    @pix_transaction ||= PixTransaction.new
    @pix_transaction.amount_reais = raw_amount_reais if defined?(raw_amount_reais)
    @pix_transaction.errors.add(:base, "Erro interno ao criar PIX.") if @pix_transaction.errors.empty?

    render :new
  end

  # ============================================================
  # PRIVATE
  # ============================================================
  private

  def pix_transaction_params
    params.require(:pix_transaction).permit(:amount_reais, :description)
  end

  def parse_amount_to_cents(raw)
    return 0 if raw.blank?

    cleaned = raw.to_s.gsub(/[^\d\.,]/, "")

    if cleaned.include?(",")
      cleaned = cleaned.tr(".", "").tr(",", ".")
    end

    (cleaned.to_f * 100).round
  end
end
