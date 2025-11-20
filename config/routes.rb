Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"

  resources :pix_transactions, only: [:index, :new, :create]
  resources :withdrawals,      only: [:index, :new, :create]

  namespace :admin do
    resources :users
  end

  post "/webhooks/witetec", to: "witetec_webhooks#receive"
  post "/webhook/sants",    to: "santsbank_webhooks#receive"
end
