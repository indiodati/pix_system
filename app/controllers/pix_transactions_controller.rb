# app/controllers/pix_transactions_controller.rb
class PixTransactionsController < ApplicationController
  before_action :authenticate_user!

  def index
    @pix_transactions = current_user.pix_transactions.order(created_at: :desc)
                               .page(params[:page])
                               .per(10)


  end

  def new
    @pix_transaction = PixTransaction.new
  end

  def create
    permitted        = pix_transaction_params
    raw_amount_reais = permitted[:amount_reais]
    amount_cents     = parse_amount_to_cents(raw_amount_reais)

    # external_id interno para rastrear a transação no seu sistema
    external_ref = "user_#{current_user.id}_tx_#{SecureRandom.hex(4)}"

    # Criamos o registro em memória com base no que o usuário pediu
    @pix_transaction = current_user.pix_transactions.new(
      description:      permitted[:description],
      amount:           amount_cents,     # será ajustado pelo valor da Witetec depois
      transaction_type: "PIX",
      status:           "PENDING",
      external_id:      external_ref
    )

    # Chama API da Witetec
    pix_service = PixService.new
    response    = pix_service.create_transaction(
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

    if response["status"] == true

       

      data     = response["data"] || {}
      pix_data = data["pix"]      || {}


      Rails.logger.warn("[WITETEC WEBHOOK] RESPOSTA DA CHAMADA PIX: #{data}")

      # 🔹 Valor bruto vindo da Witetec (mais confiável do que o do formulário)
      gateway_amount = data["amount"].to_i
      gateway_amount = amount_cents if gateway_amount.zero? # fallback

      # 🔹 Se a Witetec devolver feeAmount, usamos; se não, calculamos pela taxa do usuário
      gateway_fee = data["feeAmount"].to_i if data.key?("feeAmount")

      fee_percent = current_user.pix_fee_percent.to_f
      fee_cents =
        if gateway_fee
          gateway_fee
        else
          ((gateway_amount * fee_percent) / 100.0).round
        end

      # Atualiza o objeto com base na resposta real do gateway
      @pix_transaction.witetec_id = data["id"]                      # ESSENCIAL pro webhook
      @pix_transaction.amount     = gateway_amount                  # valor bruto oficial
      @pix_transaction.fee_amount = fee_cents                       # taxa calculada
      @pix_transaction.status     = data["status"] || "PENDING"
      @pix_transaction.pix_key    = pix_data["copyPaste"]

      @pix_transaction.save!

      # Dados para a tela de show
      @pix_qrcode     = pix_data["qrcode"]
      @pix_copy_paste = pix_data["copyPaste"]

      render :show
    else
      flash.now[:alert] = "Erro ao criar PIX: #{response['error'] || response['message']}"
      render :new
    end
  rescue => e
    Rails.logger.error "[PixTransactionsController] Erro ao criar PIX: #{e.class} - #{e.message}"
    flash.now[:alert] = "Erro interno ao criar PIX."
    render :new
  end

  private

  def pix_transaction_params
    params.require(:pix_transaction).permit(:amount_reais, :description)
  end

  def parse_amount_to_cents(raw)
    return 0 if raw.blank?
    normalized = raw.to_s.gsub(/[^\d,\.]/, "").tr(".", "").tr(",", ".")
    (normalized.to_f * 100).round
  end
end
