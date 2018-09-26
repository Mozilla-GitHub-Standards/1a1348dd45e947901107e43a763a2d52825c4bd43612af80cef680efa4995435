require_relative '../../../iam_helper'

describe OmniAuth::Strategies::OAuth2 do

  before do
    OmniAuth::Strategies::Auth0.any_instance.stubs(:no_client_id?).returns(false)
    OmniAuth::Strategies::Auth0.any_instance.stubs(:no_client_secret?).returns(false)
    OmniAuth::Strategies::Auth0.any_instance.stubs(:no_domain?).returns(false)
  end

  it "redirects callback with no params back to login" do

    get '/auth/auth0/callback'

    expect(response.status).to eq(302)
    expect(response.location).to eq('/auth/auth0?prompt=login')
  end

  it "handles callbacks with params normally" do
    get '/auth/auth0/callback?param'

    expect(response.status).to eq(302)
    expect(response.location).to eq('/auth/failure?message=csrf_detected&strategy=auth0')
  end

  it "uses autologin and sign-up flow with normal authentication" do
    get '/auth/auth0'

    expect(response.status).to eq(302)
    expect(URI.parse(response.location).query).to_not include('prompt=login')
    expect(URI.parse(response.location).query).to include('action=signup')
  end

  it "passes prompt param through" do
    get '/auth/auth0?prompt=value'

    expect(response.status).to eq(302)
    expect(URI.parse(response.location).query).to include('prompt=value')
  end

  it "passes action param through" do
    get '/auth/auth0?action=value'

    expect(response.status).to eq(302)
    expect(URI.parse(response.location).query).to include('action=value')
  end

end
