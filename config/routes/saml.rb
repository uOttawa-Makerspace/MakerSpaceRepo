# frozen_string_literal: true

get "/saml/auth" => "saml_idp#login"
get "/saml/metadata" => "saml_idp#metadata"
get "/saml/wiki_metadata" => "saml_idp#wiki_metadata"
post "/saml/auth" => "saml_idp#auth"
