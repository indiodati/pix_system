Rails.application.routes.draw do
  devise_for :users

  root "dashboard#index"

  resources :pix_transactions, only: [:index, :new, :create]
  resources :withdrawals, only: [:index, :new, :create]

  namespace :admin do
    resources :users   # sem `only`, gera todas: index, show, new, create, edit, update, destroy
  end

  post '/webhooks/witetec', to: 'witetec_webhooks#receive'

end
