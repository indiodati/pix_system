# app/controllers/withdrawals_controller.rb
class WithdrawalsController < ApplicationController
  before_action :authenticate_user!

  def index
    @withdrawals = current_user.withdrawals
                               .order(created_at: :desc)
                               .page(params[:page])
                               .per(10)
  end

  def new
    @withdrawal = current_user.withdrawals.new
    load_balances_for_new
  end

  def create
    # ------------------------------
    # Parse do valor em reais -> centavos
    # ------------------------------
    raw_amount   = params[:withdrawal][:amount].to_s
                     .gsub(/[^\d.,]/, "")
                     .gsub(".", "")
                     .tr(",", ".")
    amount_cents = (raw_amount.to_f * 100).round

    @withdrawal = current_user.withdrawals.new(
      pix_key: params[:withdrawal][:pix_key],
      amount:  amount_cents,
      status:  "PENDING"
    )

    # Mantém balances no form
    load_balances_for_new

    unless @withdrawal.valid?
      flash.now[:alert] = "Não foi possível solicitar o saque."
      return render :new
    end

    # ------------------------------
    # Descobre o gateway do usuário logado
    # ------------------------------
    gateway =
      if current_user.respond_to?(:effective_pix_gateway)
        current_user.effective_pix_gateway
      else
        current_user.pix_gateway rescue "witetec"
      end

    gateway = "witetec" unless %w[witetec santsbank].include?(gateway)

    Rails.logger.info "[WITHDRAW CREATE] user_id=#{current_user.id} gateway=#{gateway} amount_cents=#{amount_cents}"

    # ------------------------------
    # Chamada pro provider certo
    # ------------------------------
    if gateway == "santsbank"
      create_with_sants_gateway(amount_cents)
    else
      create_with_witetec_gateway(amount_cents)
    end
  rescue => e
    Rails.logger.error "Erro ao criar saque: #{e.class} - #{e.message}"
    flash.now[:alert] = "Erro interno ao solicitar saque."
    load_balances_for_new
    render :new
  end

  private

  # ============================================================
  # WITETEC
  # ============================================================
  def create_with_witetec_gateway(amount_cents)
    pix_service = PixService.new
    response    = pix_service.create_withdrawal(
      amount_cents:        amount_cents,
      pix_key:             @withdrawal.pix_key,
      pix_key_type:        params[:withdrawal][:pix_key_type].presence || "CPF",
      seller_external_ref: "user_#{current_user.id}"
    )

    if response["status"] == true
      data = response["data"] || {}

      @withdrawal.status     = data["status"].presence || "PENDING"
      @withdrawal.gateway_id = data["id"]              # 👈 ID no gateway (Witetec)

      @withdrawal.save!
      redirect_to withdrawals_path, notice: "Saque solicitado com sucesso!"
    else
      msg = response["error"] || response["message"] || "Erro ao solicitar saque."

      @withdrawal.status = "FAILED"
      @withdrawal.errors.add(:base, msg)

      flash.now[:alert] = "Erro ao solicitar saque: #{msg}"
      render :new
    end
  end

  # ============================================================
  # SANTS BANK
  # ============================================================
  def create_with_sants_gateway(amount_cents)
    sants_service = SantsWithdrawService.new
    response      = sants_service.withdraw(
      amount_cents: amount_cents,
      pix_key:      @withdrawal.pix_key,
      pix_key_type: params[:withdrawal][:pix_key_type].presence || "CPF"
    )

    Rails.logger.info "[WITHDRAW SANTS] response=#{response.inspect}"

    if response.is_a?(Hash) && response["sucesso"] == true
      # Ex de resposta:
      # {
      #   "sucesso": true,
      #   "mensagem": "Transação salva com Sucesso",
      #   "codigoTransacao": "nbyayb64-....",
      #   "dataHoraTransacao": "2024-11-04T14:47:12.221Z"
      # }

      @withdrawal.status     = "PROCESSING" # ou "PENDING", tanto faz pro teu fluxo
      @withdrawal.gateway_id = response["codigoTransacao"]

      @withdrawal.save!
      redirect_to withdrawals_path, notice: "Saque solicitado com sucesso!"
    else
      msg =
        if response.is_a?(Hash)
          response["mensagem"] || response["message"] || response["error"]
        end

      msg ||= "Erro ao solicitar saque na Sants."

      @withdrawal.status = "FAILED"
      @withdrawal.errors.add(:base, msg)

      flash.now[:alert] = "Erro ao solicitar saque: #{msg}"
      render :new
    end
  end

  # ============================================================
  # BALANCES
  # ============================================================
  def load_balances_for_new
    @available_balance_reais  = current_user.balance_reais
    @per_withdraw_limit_reais = current_user.withdraw_limit.to_f
    @max_withdrawable_reais   = [@available_balance_reais, @per_withdraw_limit_reais].min
  end
end
