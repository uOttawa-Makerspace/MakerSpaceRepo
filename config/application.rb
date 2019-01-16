require File.expand_path('../boot', __FILE__)

require 'csv'
require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MakerSpaceRepo
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    config.time_zone = 'Eastern Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    # Do not swallow errors in after_commit/after_rollback callbacks.
    config.active_record.raise_in_transactional_callbacks = true

    SamlIdp.configure do |config|
      config.x509_certificate = <<-CERT
-----BEGIN CERTIFICATE-----
MIIDYTCCAkigAwIBAgIBADANBgkqhkiG9w0BAQ0FADBKMQswCQYDVQQGEwJjYTEQ
MA4GA1UECAwHT250YXJpbzESMBAGA1UECgwJTWFrZXJSZXBvMRUwEwYDVQQDDAxt
YWtlcmVwby5jb20wHhcNMTkwMTE1MDIzMjQyWhcNMjAwMTE1MDIzMjQyWjBKMQsw
CQYDVQQGEwJjYTEQMA4GA1UECAwHT250YXJpbzESMBAGA1UECgwJTWFrZXJSZXBv
MRUwEwYDVQQDDAxtYWtlcmVwby5jb20wggEjMA0GCSqGSIb3DQEBAQUAA4IBEAAw
ggELAoIBAgDHRSI8vlVknlvkua/cPdUSP5bGAeIMPrYSF2qxbar/G/xWEYaKWFmc
rGYeKrl2i75FbFAc4hdwVvAFwyCd20ZSZribFxSy6yazi9/AwCNjd3oqsoRyznjF
6VvM38CULKeKS7jb4Q+ZgCfuVfyZbvcV5TO2pS4KmL67EPiSbNmKvA2BPpDRZg9Q
qXc4mNYfJp44Rd8xbhMmJGPd48MVZxZrOxNWRTaZ27MbH7uAd5ywsxc+wM+p4Wgt
/b1Ubjm8iMdsNHx2d3vOmca6/Rk+HxX/IzcJFepitdhVgwkg4hApNB2NM5oHEFqI
35utkHP5+agTtRP4mWJ20faEyl3jLlbURwIDAQABo1AwTjAdBgNVHQ4EFgQUvasd
XJVcn9j6h/rOTGFVfRwRfXUwHwYDVR0jBBgwFoAUvasdXJVcn9j6h/rOTGFVfRwR
fXUwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQ0FAAOCAQIAmHbN/N2U27Ks6lCW
ddfTcxOLIIQOcNS/eK9DNlrtml7tZ5IHXFOpXbThfX/M1n4zrRwjKbSxbfpXZEI2
Iq7QzLXF7B1UGH5SgoV71h4BLr0Fxwe11jiNfGDQ1HvCb7kNSaZ6tPw45DIxrUu1
oyY/xaFFzvKLXOWonNH3daGTpiswy41K+8IAmm4B1Th0i07ZSPPvW9sAcdE3TCcM
+d5D3IWFMAmVlYImRafaNeI6Q2qmfQmcxeN33D3ezoCBn/i9SBU0D63vpVWiATe0
WXOuHEpP45F+yiuYzUcHl/vAFtQRME/PGXXxnPErgIh8Eluz5/4iM8mMERTPDDZr
2wljn2Y=
-----END CERTIFICATE-----
      CERT

      config.secret_key = <<-PRIVKEY
-----BEGIN PRIVATE KEY-----
MIIEwQIBADANBgkqhkiG9w0BAQEFAASCBKswggSnAgEAAoIBAgDHRSI8vlVknlvk
ua/cPdUSP5bGAeIMPrYSF2qxbar/G/xWEYaKWFmcrGYeKrl2i75FbFAc4hdwVvAF
wyCd20ZSZribFxSy6yazi9/AwCNjd3oqsoRyznjF6VvM38CULKeKS7jb4Q+ZgCfu
VfyZbvcV5TO2pS4KmL67EPiSbNmKvA2BPpDRZg9QqXc4mNYfJp44Rd8xbhMmJGPd
48MVZxZrOxNWRTaZ27MbH7uAd5ywsxc+wM+p4Wgt/b1Ubjm8iMdsNHx2d3vOmca6
/Rk+HxX/IzcJFepitdhVgwkg4hApNB2NM5oHEFqI35utkHP5+agTtRP4mWJ20faE
yl3jLlbURwIDAQABAoIBAUIDjh8PctyddZXlSfQta7va4wj/sLIbyFdf+JGE4kQX
MlYVAjwsnqs/lajiwIQcMVFwW23mHJuzwVo3VUPWU4qSyw9d6xaGvlB2ww5o2JBo
EUm50BT0f6AY+bd6XKL51BsFkN0Oxws0IIZdaAwwbZyMTMByIjmSdoUkTyS6+Kp0
Lq2OSpOPnzJSaDvZPkjTy5FNRUPhC3LD2P4X3Ag87uK2ZMBE2Tr7tHCNMGPndZhF
p52lp231J4JmftTOlo/4RUDdd5eCIGc41qoNrsfbwgwco05iHDNjyZjqPV0itf4b
GNXf0Pi1aeC0GM8ZBv1Gs1tNpRR/usiG1HCa0hye4Y9JAoGBDpMZo5bczYQuKdxS
lRlRrawvernlpCZ+t7NMmgc3XVFujWxLbpLTlTlK8+glhhCyaxIso1H/qnUjTUrw
g+tJLGp24Cmdd9XOXGKKD0OKkqxyt/duq1FTZLRlDMPMPTWuTgy1JCqVKRrb8JmP
3r6Jg+whYfwWeUk/5Yp78TSXjIRTAoGBDawjG/iPzdUYDHJRhl3IJzvin0SmZzHu
8j4VSjwgJTULk8jSyyd1W5UxP1WJaDY+b72Jj2f+WlzGeOmOLaIxB2P0DqPr7W9F
MmWy2u/nFpjsAH1Tf3pHnWvMilBrqbIgmFe/XH34QYwJAPCVURxKCUU+ZI0uOQN6
97c8Dp4v/fG9AoGBDTC0E4mFa7okzV3In4e6lCMxFTEI0/bC2B49RWkigiIgm31X
B0t6kaK4YuXGj/6sepqIK4cai3pX6KvZ4IogP0JbM6R2Du5BRPspV4cY8oV/jV8x
mXqQrqNUkKjjPsJGbfyyM3kWZY0ZYDaaLkzix7H8xGERNdNFMMiUQ0gFn/ZhAoGB
BpVQAnPYqj9k6PlSj+QwL9QB9rZTeXTtnO6PycLRp5i3Dl2wQemp9IMNx3UkSG11
+s/EoKxuKIxrdGTg9NAX03spVLNRMm5VX0Lgr9K77oGLgWDXB5aVTRNO1XqLnJYM
Y848cgiltMn8u9sbyoZYj8YrmLbx/rnSR9yOqms4qInxAoGBAKKnQsbdU1QMKcB3
vXgGOHWRpIZA+qmFufR3jqT/84ZDi0fsgEozln6JrDHBd/dh3tpjJNar1G5dyZ9+
GthYf9e8UZ6HD3pDefx27+OoWwVrsoI9mx0fTHFIw9s7oG1hL17l9cVbmEca8Ljs
Q4n31ou2DuBLscfEsS+Nzo3nZWy0
-----END PRIVATE KEY-----
      PRIVKEY

      service_providers = {
          "wiki.makerepo.com" => {
              response_hosts: ["wiki.makerepo.com"]
          }
      }

      config.name_id.formats = {
          email_address: -> (p) { p[:email_address] },
          transient: -> (p) { p[:id] },
          persistent: -> (p) { p[:id] }
      }

      config.attributes = {
          "email_address": {
              :getter => -> (p) { p[:email_address] }
          },
          "username": {
              :getter => -> (p) { p[:username] }
          },
          "name": {
              :getter => -> (p) { p[:name] }
          }
      }

      config.service_provider.metadata_persister = ->(identifier, settings) {
        fname = identifier.to_s.gsub(/\/|:/,"_")
        FileUtils.mkdir_p(Rails.root.join('cache', 'saml', 'metadata').to_s)
        File.open Rails.root.join("cache/saml/metadata/#{fname}"), "r+b" do |f|
          Marshal.dump settings.to_h, f
        end
      }

      # `identifier` is the entity_id or issuer of the Service Provider,
      # `service_provider` is a ServiceProvider object. Based on the `identifier` or the
      # `service_provider` you should return the settings.to_h from above
      config.service_provider.persisted_metadata_getter = ->(identifier, service_provider){
        fname = identifier.to_s.gsub(/\/|:/,"_")
        FileUtils.mkdir_p(Rails.root.join('cache', 'saml', 'metadata').to_s)
        full_filename = Rails.root.join("cache/saml/metadata/#{fname}")
        if File.file?(full_filename)
          File.open full_filename, "rb" do |f|
            Marshal.load f
          end
        end
      }

      config.service_provider.finder = ->(issuer_or_entity_id) do
        service_providers[issuer_or_entity_id]
      end
    end
  end
end
