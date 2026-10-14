Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins "*"  # Restrict in production (e.g., 'yourapp.com')
    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options ],
      expose: [ "Authorization" ]
  end
end
