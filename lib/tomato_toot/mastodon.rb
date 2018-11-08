require 'addressable/uri'
require 'httparty'
require 'rest-client'
require 'json'

module TomatoToot
  class Mastodon
    def initialize(params)
      @params = params.clone
    end

    def toot(text, options = {})
      values = options.clone
      values[:status] = text
      return HTTParty.post(create_uri('/api/v1/statuses'), {
        body: values.to_json,
        headers: {
          'Content-Type' => 'application/json',
          'User-Agent' => Package.user_agent,
          'Authorization' => "Bearer #{@params['token']}",
          'X-Mulukhiya' => Package.full_name,
        },
        ssl_ca_file: ENV['SSL_CERT_FILE'],
      })
    end

    def upload(path)
      response = RestClient.post(
        create_uri('/api/v1/media').to_s,
        {file: File.new(path, 'rb')},
        {
          'User-Agent' => Package.user_agent,
          'Authorization' => "Bearer #{@params['token']}",
        },
      )
      return JSON.parse(response.body)['id'].to_i
    end

    def upload_remote_resource(uri)
      path = File.join(ROOT_DIR, 'tmp/media', Digest::SHA1.hexdigest(uri))
      File.write(path, fetch(uri))
      return upload(path)
    ensure
      File.unlink(path) if File.exist?(path)
    end

    private

    def fetch(uri)
      return HTTParty.get(uri, {
        headers: {
          'User-Agent' => Package.user_agent,
        },
        ssl_ca_file: ENV['SSL_CERT_FILE'],
      })
    rescue => e
      raise ExternalServiceError, "外部ファイルが取得できません。 (#{e.message})"
    end

    def create_uri(href)
      uri = Addressable::URI.parse(@params['url'])
      uri.path = href
      return uri
    end
  end
end
