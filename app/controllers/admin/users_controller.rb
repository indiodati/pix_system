# app/controllers/admin/users_controller.rb
module Admin
  class UsersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_user, only: [:show, :edit, :update, :destroy]

    def index
      @users = User.order(:id)
    end

    # 👇 ESSA ACTION PRECISA EXISTIR ASSIM
    def show
      redirect_to admin_users_path
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)

      if @user.save
        redirect_to admin_users_path, notice: "Usuário criado com sucesso."
      else
        flash.now[:alert] = "Erro ao criar usuário."
        render :new
      end
    end

    def edit
    end

    def update
      attrs = user_params.dup

      if attrs[:password].blank?
        attrs.delete(:password)
        attrs.delete(:password_confirmation)
      end

      if @user.update(attrs)
        redirect_to admin_users_path, notice: "Usuário atualizado com sucesso."
      else
        flash.now[:alert] = "Erro ao atualizar usuário."
        render :edit
      end
    end

    def destroy
      if @user == current_user
        redirect_to admin_users_path, alert: "Você não pode excluir a si mesmo."
      else
        @user.destroy
        redirect_to admin_users_path, notice: "Usuário excluído com sucesso."
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def require_admin!
      unless current_user&.admin?
        redirect_to root_path, alert: "Acesso não autorizado."
      end
    end

    def user_params
      params.require(:user).permit(
        :email,
        :name,
        :phone,
        :document,
        :admin,
        :pix_fee_percent,
        :password,
        :password_confirmation
      )
    end
  end
end
