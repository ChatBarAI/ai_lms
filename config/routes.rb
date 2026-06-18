Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    registrations: "users/registrations"
  }

  # Kinde SSO (uses kinde_sdk gem directly, not OmniAuth)
  get "kinde/login",            to: "kinde_auth#login",            as: :kinde_login
  get "kinde/callback",         to: "kinde_auth#callback",         as: :kinde_callback
  get "kinde/logout",           to: "kinde_auth#logout",           as: :kinde_logout
  get "kinde/logout_callback",  to: "kinde_auth#logout_callback",  as: :kinde_logout_callback
  # Per-organisation SSO entry point (e.g. bookmarked by client staff)
  get "auth/org/:org_slug",     to: "kinde_auth#org_login",        as: :org_sso_login
  # Email-domain lookup: returns the SSO sign-in URL for a given email if its
  # domain is registered to an org, so the sign-in page can auto-redirect.
  get "auth/sso_check",         to: "kinde_auth#sso_check",        as: :sso_check
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "pwa/icons/:kind.png" => "pwa#icon", as: :pwa_icon,
      constraints: { kind: /192|512|maskable-512|apple-touch/ }

  # Core LMS resources (controllers to be added in a follow-up pass)
  resources :subjects, only: [ :index, :show ] do
    resources :courses, only: [ :index ]
  end

  resources :courses do
    member do
      post :publish
      post :unpublish
      get   "certificate_layout", to: "courses#certificate_layout"
      patch "certificate_layout", to: "courses#update_certificate_layout"
    end
    resources :lessons do
      member do
        post :start
        post :submit_quiz
        post :publish
        post :unpublish
        get   "video/youtube",  to: "lessons#video_youtube_edit",  as: :video_youtube
        patch "video/youtube",  to: "lessons#video_youtube_update"
        get   "video/upload",   to: "lessons#video_upload_edit",   as: :video_upload
        patch "video/upload",   to: "lessons#video_upload_update"
        get   "video/chatbar",  to: "lessons#video_chatbar",       as: :video_chatbar
        get   "video/synthesia", to: "lessons#video_synthesia",    as: :video_synthesia
        get   "video/heygen",    to: "lessons#video_heygen",       as: :video_heygen
        post  "video/import",   to: "lessons#import_recording",    as: :import_recording
        post  "video/import_synthesia", to: "lessons#import_synthesia_video", as: :import_synthesia_video
        post  "video/import_heygen", to: "lessons#import_heygen_video", as: :import_heygen_video
        get   "video/poster",   to: "lessons#poster_edit",         as: :poster
        patch "video/poster",   to: "lessons#poster_update"
        delete "video/poster",  to: "lessons#destroy_poster",      as: :destroy_poster
        delete "video",         to: "lessons#destroy_video",       as: :destroy_video
      end
      resources :questions do
        collection do
          post :reorder
        end
      end
      resources :question_generation_tasks, only: [ :create ] do
        member do
          post :simulate
        end
      end
      resources :ratings, only: [ :create, :update, :destroy ]
      resources :lesson_materials do
        collection do
          post :reorder
        end
        member do
          post :acknowledge
        end
      end
    end
    resources :enrollments, only: [ :create, :destroy ]
    resource  :certificate, only: [ :show ]
  end

  get "/certificates/:token", to: "verifications#show", as: :verify_certificate

  resources :progresses, only: [ :update ]

  resources :tags, only: [ :show ]
  namespace :admin do
    root "dashboard#index"
    resources :users do
      member do
        post :enroll
        post :reset_password
      end
      collection do
        get :export
      end
    end
    resources :organizations
    resources :subjects
    resources :courses do
      member do
        get :report
        get   "certificate_layout", to: "courses#certificate_layout"
        patch "certificate_layout", to: "courses#update_certificate_layout"
      end
      resources :lessons, only: [ :index ] do
        member do
          get :report
        end
      end
    end
    resources :tags
    resource  :site_setting, only: [ :edit, :update ]
    resources :certificates, only: [ :index, :destroy ]
  end

  # Public API for embedding LMS widgets on customer sites
  namespace :api do
    resources :lessons, only: [ :show ], param: :token
    match "question_generation_tasks/:token/callback",
          to: "question_generation_tasks#callback",
          as: :question_generation_task_callback,
          via: [ :post, :put, :patch ]
  end

  get "/me" => "home#me", as: :me
  resource :profile, only: [ :show, :edit, :update ]

  # Defines the root path route ("/")
  # root "courses#index"
  root "home#index"
end
