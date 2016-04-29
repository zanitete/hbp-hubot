http = require 'request-promise'

module.exports = (robot) ->
  hbpSuperusers = [
    '226241'
  ]
  userApiUrl = "https://services-dev.humanbrainproject.eu/idm/v1/api/user"
  oidcUrl = "https://services-dev.humanbrainproject.eu/oidc"

  clientId = process.env.HUBOT_HBP_OIDC_CLIENTID
  clientSecret = process.env.HUBOT_HBP_OIDC_CLIENTSECRET

  if !clientId or !clientSecret
    robot.logger.error 'HUBOT_HBP_OIDC_CLIENTID or HUBOT_HBP_OIDC_CLIENTSECRET is not set.'
    throw new Error('Missing OIDC configuration');

  # ########################
  # util functions
  getToken = () ->
    http({
        url: "#{oidcUrl}/token",
        qs: {
          grant_type: 'client_credentials',
          client_secret: clientSecret,
          client_id: clientId
        },
        json: true
      }).then (body) -> body.access_token

  getUser = (msg, id, token) ->
    msg.http("#{userApiUrl}/#{id}")
      .header('Authorization', "Bearer #{token}")
      .get()

  buildUserinfo = (u) -> u.displayName + ' (' + u.id + ', ' + u.username + ')'

  # ########################
  # user bot
  robot.respond /user (.*)/i, (msg) ->
    userinput = escape(msg.match[1])
    if userinput == 'me'
      userinput = msg.message.user.id

    getToken().then (token) ->
      getUser(msg, userinput, token) (err, res, body) ->
          switch res.statusCode
            when 200
              user = JSON.parse(body)
              msg.send buildUserinfo(user)
            when 404
              msg.http("#{userApiUrl}/searchByText?str=#{userinput}")
                .header('Authorization', "Bearer #{token}")
                .get() (err, res, body) ->
                  json = JSON.parse(body)
                  users = json._embedded.users
                  if users.length > 0
                    text = (users.map buildUserinfo).join(', ')
                    msg.send text
                  else
                    msg.send "No idea who #{userinput} is"

  # ########################
  # debug bot (admin only)
  robot.respond /debug/i, (msg) ->
    userid = msg.message.user.id
    token = process.env.HUBOT_OIDC_SECRET
    if (hbpSuperusers.indexOf userid) == -1
      getUser(msg, userid, token) (err, res, body) ->
        name = JSON.parse(body).givenName
        msg.send "Sorry #{name}, ask an admin to do it for you"
      return
    console.log Object(msg)

  # ########################
  # default bot answer
  robot.catchAll (msg) ->
    if msg.message.text
      msg.send "what do you mean by '#{msg.message.text}'? I'm just a Bluesky hubot!"
