class ApplicationController < ActionController::Base
  # Redirecionamento após login
  def after_sign_in_path_for(resource)
    if resource.admin?
      admin_users_path
    else
      root_path
    end
  end

  # Permitir campos extras do Devise
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # Para cadastro
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :phone, :document])
    # Para edição de conta
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :phone, :document])
  end
end
