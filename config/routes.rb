Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post 'auth/login', to: 'auth#login'
      post 'auth/signup', to: 'auth#signup'
      delete 'auth/logout', to: 'auth#logout'
      post 'auth/password', to: 'passwords#create'
      post 'auth/password/verify', to: 'passwords#verify_code'
      put 'auth/password', to: 'passwords#update'
      patch 'auth/password', to: 'passwords#update'
      get 'auth/refresh-user', to: 'auth#refresh_user'

      post 'conversation/new', to: 'conversations#new'
      get 'conversations/admin_conversation', to: 'conversations#admin_conversation'

      resources :conversations, only: [] do
        resources :messages, only: [:index, :create]
      end

      get 'user', to: 'users#show'
      post 'user', to: 'users#update'
      post 'user/delete', to: 'users#destroy'
      get 'users/search', to: 'users#search'
      get 'user/conversations', to: 'conversations#index'
      get 'subscription/status', to: 'subscriptions#status'
      get 'subscriptions', to: 'subscriptions#show'
      post 'subscription/validate', to: 'subscriptions#validate'
      post 'subscription/create_basic_subscription', to: 'subscriptions#create_basic_subscription'
      post 'subscription/create_pro_subscription', to: 'subscriptions#create_pro_subscription'
      post 'subscription/sync', to: 'subscriptions#sync'
      post 'webhooks/revenuecat', to: 'webhooks#revenuecat'
      post 'receipts', to: 'subscriptions#receipts'

      get 'onboarding', to: 'onboarding#show'
      get 'onboarding/completed_onboarding', to: 'onboarding#completed_onboarding'

      resources :timer_runs, only: [:index, :create, :update]
    end
  end
end
