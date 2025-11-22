# app/controllers/admin/users_controller.rb
class Admin::UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_user, only: %i[show edit update destroy]

  # =========================================
  # INDEX
  # =========================================
  def index
    @users = User.order(:id)

    # --------- MÉTRICAS GERAIS ----------
    @total_balance_cents = User.sum(:balance_cents)
    @total_balance_reais = @total_balance_cents.to_i / 100.0

    paid_pix_scope = PixTransaction.paid_pix

    @total_pix_volume_cents  = paid_pix_scope.sum(:amount)
    @total_pix_volume_reais  = @total_pix_volume_cents.to_i / 100.0

    @total_fees_earned_cents = paid_pix_scope.sum(:fee_amount)
    @total_fees_earned_reais = @total_fees_earned_cents.to_i / 100.0

    # --------- ÚLTIMAS 10 TRANSAÇÕES PIX ----------
    @recent_pix_transactions = PixTransaction
                                 .includes(:user)
                                 .order(created_at: :desc)
                                 .limit(10)

    # --------- DADOS DO GRÁFICO (últimos 30 dias) ----------
    chart_scope  = paid_pix_scope.where("created_at >= ?", 30.days.ago)

    daily_amounts = chart_scope.group("DATE(created_at)").sum(:amount)
    daily_fees    = chart_scope.group("DATE(created_at)").sum(:fee_amount)

    dates = (daily_amounts.keys + daily_fees.keys).uniq.sort

    @pix_chart_labels = dates.map { |d| I18n.l(d, format: "%d/%m") }
    @pix_chart_values = dates.map { |d| (daily_amounts[d].to_i / 100.0).round(2) }
    @pix_chart_fees   = dates.map { |d| (daily_fees[d].to_i    / 100.0).round(2) }
  end

  # =========================================
  # SHOW
  # =========================================
  def show
  end

  # =========================================
  # NEW
  # =========================================
  def new
    @user = User.new
  end

  # =========================================
  # CREATE
  # =========================================
  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to admin_users_path, notice: "Usuário criado com sucesso."
    else
      flash.now[:alert] = "Não foi possível criar o usuário."
      render :new
    end
  end

  # =========================================
  # EDIT
  # =========================================
  def edit
  end

  # =========================================
  # UPDATE
  # =========================================
  def update
    attrs = user_params

    # se não mandar senha, não tenta atualizar senha
    if attrs[:password].blank?
      attrs.delete(:password)
      attrs.delete(:password_confirmation)
    end

    if @user.update(attrs)
      redirect_to admin_users_path, notice: "Usuário atualizado com sucesso."
    else
      flash.now[:alert] = "Não foi possível atualizar o usuário."
      render :edit
    end
  end

  # =========================================
  # DESTROY
  # =========================================
  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "Você não pode excluir o próprio usuário."
    else
      @user.destroy
      redirect_to admin_users_path, notice: "Usuário excluído com sucesso."
    end
  end

  private

  # =========================================
  # CALLBACKS
  # =========================================
  def set_user
    @user = User.find(params[:id])
  end

  # =========================================
  # STRONG PARAMS
  # =========================================
  def user_params
    params.require(:user).permit(
      :name,
      :email,
      :password,
      :password_confirmation,
      :phone,
      :pix_fee_percent,
      :withdraw_limit,
      :balance_cents,
      :pix_gateway,
      :admin
    )
  end

  # =========================================
  # AUTORIZAÇÃO
  # =========================================
  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: "Você não tem permissão para acessar essa área."
    end
  end
end
