module.exports = (robot) ->

  robot.respond /whois (.*)/i, (msg) ->
    unless process.env.HUBOT_OIDC_SECRET
      robot.logger.error 'HUBOT_OIDC_SECRET is not set.'
      return msg.send "You must configure the HUBOT_OIDC_SECRET environment variable"
    # TODO: obtain a token
    token = process.env.HUBOT_OIDC_SECRET
    userid = escape(msg.match[1])
    msg.http("https://services-dev.humanbrainproject.eu/idm/v1/api/user/#{userid}")
      .header('Authorization', "Bearer #{token}")
      .get() (err, res, body) ->
        if !err
          try
            json = JSON.parse(body)
            msg.send "#{json.displayName}"
          catch error
            msg.send "I don't know, for sure not an HBP user!"
        else
          msg.send "I don't know, for sure not an HBP user!"

