Tarpon::Client.configure do |c|
    c.public_api_key = ENV["TARPON_PUBLIC_KEY"]
    c.secret_api_key = ENV["TARPON_SECRET_KEY"]
    c.timeout        = 5 # a global timeout in seconds for http requests to RevenueCat server, default is 5 seconds
  end
