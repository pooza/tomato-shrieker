module TomatoShrieker
  class PiefedShrieker < LemmyShrieker
    def login
      response = http.post('/api/v3/user/login', {
        body: {
          username_or_email: @params[:user_id],
          password: (@params[:password].decrypt rescue @params[:password]),
        },
      })
      @jwt = response['jwt']
      logger.info(clipper: self.class.to_s, method: __method__, url: uri.to_s)
    end

    def exec(body)
      template = search_template(body)
      data = {
        name: template.to_s.gsub(/[\r\n[:blank:]]+/, ' '),
        body: template.to_s,
        community_id: template.source['/dest/lemmy/community_id'],
      }
      Ginseng::URI.scan(data[:body]).each {|uri| data[:name].gsub!(uri.to_s, '')}
      data[:name].ellipsize!(config['/lemmy/subject/max_length'])
      uri = (template.entry || template.source).uri rescue Ginseng::URI.scan(template.to_s).first
      data[:url] = uri.to_s if uri
      return http.post('/api/v3/post', {
        body: data,
        headers: {'Authorization' => "Bearer #{@jwt}"},
      })
    end
  end
end
