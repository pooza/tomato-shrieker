module TomatoShrieker
  class PiefedShrieker
    include Package

    attr_reader :http

    def initialize(params = {})
      @params = params.deep_symbolize_keys
      @http = HTTP.new
      @http.base_uri = uri
      login
    end

    def uri
      @uri ||= Ginseng::URI.parse("https://#{@params[:host]}")
      return @uri if @uri&.absolute?
    end

    def login
      response = http.post('/api/alpha/user/login', {
        body: {
          username: @params[:user_id],
          password: (@params[:password].decrypt rescue @params[:password]),
        },
      })
      @jwt = response['jwt']
      logger.info(clipper: self.class.to_s, method: __method__, url: uri.to_s)
    end

    def exec(body)
      template = search_template(body)
      data = {
        title: template.to_s.gsub(/[\r\n[:blank:]]+/, ' '),
        body: template.to_s,
        community_id: template.source['/dest/piefed/community_id'],
      }
      Ginseng::URI.scan(data[:body]).each {|uri| data[:body].gsub!(uri.to_s, '')}
      data[:title].ellipsize!(config['/piefed/subject/max_length'])
      uri = (template.entry || template.source).uri rescue Ginseng::URI.scan(template.to_s).first
      data[:url] = uri.to_s if uri
      return http.post('/api/alpha/post', {
        body: data,
        headers: {'Authorization' => "Bearer #{@jwt}"},
      })
    end

    def search_template(body)
      unless entry = body[:template].entry
        return body[:template].source.create_template(:piefed, body[:template].to_s)
      end
      return entry.create_template(:piefed)
    rescue
      return body[:template]
    end
  end
end
