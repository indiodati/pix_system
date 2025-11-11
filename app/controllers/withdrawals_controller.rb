class WithdrawalsController < ApplicationController
  before_action :authenticate_user!

  def index
    @withdrawals = current_user.withdrawals
                               .order(created_at: :desc)
                               .page(params[:page])
                               .per(10) # quantidade por página, ajuste se quiser
  end


  def new
    @withdrawal = current_user.withdrawals.new
    load_balances_for_new
  end

  def create
    raw_amount   = params[:withdrawal][:amount].to_s
                     .gsub(/[^\d.,]/, '')
                     .gsub('.', '')
                     .tr(',', '.')
    amount_cents = (raw_amount.to_f * 100).round

    @withdrawal = current_user.withdrawals.new(
      pix_key: params[:withdrawal][:pix_key],
      amount:  amount_cents,
      status:  "PENDING"
    )

    if @withdrawal.valid?
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
        @withdrawal.witetec_id = data["id"]              # 👈 ID da Witetec

        @withdrawal.save!
        redirect_to withdrawals_path, notice: "Saque solicitado com sucesso!"
      else
        # ❌ NÃO salvar no banco quando a Witetec recusar
        msg = response["error"] || response["message"] || "Erro ao solicitar saque."

        @withdrawal.status = "FAILED" # só para exibir no form, não será salvo
        @withdrawal.errors.add(:base, msg)

        flash.now[:alert] = "Erro ao solicitar saque: #{msg}"
        load_balances_for_new
        render :new
      end
    else
      flash.now[:alert] = "Não foi possível solicitar o saque."
      load_balances_for_new
      render :new
    end
  rescue => e
    Rails.logger.error "Erro ao criar saque: #{e.class} - #{e.message}"
    flash.now[:alert] = "Erro interno ao solicitar saque."
    load_balances_for_new
    render :new
  end

  private

  def load_balances_for_new
    @available_balance_reais  = current_user.balance_reais
    @per_withdraw_limit_reais = current_user.withdraw_limit.to_f
    @max_withdrawable_reais   = [@available_balance_reais, @per_withdraw_limit_reais].min
  end
end
