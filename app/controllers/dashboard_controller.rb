class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    if current_user.admin?
      redirect_to admin_users_path
    else
      @pix_transactions = current_user.pix_transactions
                                      .where("LOWER(transaction_type) = ?", "pix")
                                      .order(created_at: :desc)
                                      .limit(5)

      @withdrawals = current_user.withdrawals.order(created_at: :desc).limit(5)

      @balance_reais = current_user.balance_reais
    end
  end
end
