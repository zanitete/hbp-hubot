module.exports = (robot) ->

  robot.respond /user (.*)/i, (msg) ->
    unless process.env.HUBOT_OIDC_SECRET
      robot.logger.error 'HUBOT_OIDC_SECRET is not set.'
      return msg.send "You must configure the HUBOT_OIDC_SECRET environment variable"
    # TODO: obtain a token
    token = process.env.HUBOT_OIDC_SECRET
    userid = escape(msg.match[1])
    userApiUrl = "https://services-dev.humanbrainproject.eu/idm/v1/api/user"

    buildUserinfo = (u) -> u.displayName + ' (' + u.id + ', ' + u.username + ')'

    msg.http("#{userApiUrl}/#{userid}")
      .header('Authorization', "Bearer #{token}")
      .get() (err, res, body) ->
        switch res.statusCode
          when 200
            user = JSON.parse(body)
            msg.send buildUserinfo(user)
          when 404
            msg.http("#{userApiUrl}/searchByText?str=#{userid}")
              .header('Authorization', "Bearer #{token}")
              .get() (err, res, body) ->
                json = JSON.parse(body)
                users = json._embedded.users
                if users.length > 0
                  text = (users.map buildUserinfo).join(', ')
                  msg.send text
                else
                  msg.send "No idea who #{userid} is"

