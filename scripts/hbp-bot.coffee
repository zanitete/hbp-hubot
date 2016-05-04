http = require 'request-promise'

module.exports = (robot) ->
  hbpSuperusers = [
    '226241'
  ]
  userApiUrl = "https://services-dev.humanbrainproject.eu/idm/v1/api/user"
  oidcUrl = "https://services-dev.humanbrainproject.eu/oidc"
  profileUrl = "https://services-dev.humanbrainproject.eu/idm/manager/#/user"
  ciUrl = "https://bbpcode.epfl.ch/ci/job"

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

  getUser = (id, token) ->
    http({
        url: "#{userApiUrl}/#{id}",
        headers: {
          authorization: "Bearer #{token}"
        },
        json: true
      })

  buildUserinfo = (u) -> "#{u.displayName} - #{u.username} - #{u.id} [more](#{profileUrl}/#{u.username})"

  # ########################
  # user bot
  robot.respond /user (.*)/i, (msg) ->
    userinput = escape(msg.match[1])
    if userinput == 'me'
      userinput = msg.message.user.id

    getToken().then (token) ->
      getUser(userinput, token)
        .then (user) ->
                msg.send buildUserinfo(user)
             ,(error) ->
                msg.http("#{userApiUrl}/searchByText?str=#{userinput}")
                  .header('Authorization', "Bearer #{token}")
                  .get() (err, res, body) ->
                    json = JSON.parse(body)
                    users = json._embedded.users
                    if users.length > 0
                      text = (users.map buildUserinfo).join('\n\n')
                      msg.send text
                    else
                      msg.send "No idea who #{userinput} is"

  # ########################
  # release bot (admin only)
  components = [{
    name: 'collaboratory-frontend',
    params: [
      { name: 'GERRIT_REFSPEC', value: 'refs/heads/master' },
      { name : 'GERRIT_BRANCH', value : 'master' },
      { name: 'release', value: 'none' }
    ]
  },{
    name: 'collaboratory-extension-core',
    params: [
      { name: 'GERRIT_REFSPEC', value: 'refs/heads/master' },
      { name : 'GERRIT_BRANCH', value : 'master' },
      { name: 'release', value: 'none' }
    ]
  },{
    name: 'hbp-identity-service',
    params: [
      { name: 'GERRIT_REFSPEC', value: 'refs/heads/master' },
      { name : 'GERRIT_BRANCH', value : 'master' },
      { name: 'release', value: 'false' }
    ]
  },{
    name: 'collaboratory-functional-tests',
    params: [
      { name: 'GERRIT_REFSPEC', value: 'refs/heads/master' },
      { name : 'GERRIT_BRANCH', value : 'master' },
      { name: 'test_env', value: 'prod' }
    ]
  }]

  robot.respond /release (.*)/i, (msg) ->
    unless process.env.HUBOT_HBP_CI_USERNAME and process.env.HUBOT_HBP_CI_USER_TOKEN and process.env.HUBOT_HBP_CI_BUILD_TOKEN
      robot.logger.error 'Jenkins config missing'
      return msg.send "You must set Jenkins env variables first"

    userid = msg.message.user.id
    getToken().then (token) ->
      getUser(userid, token).then (user) ->
        if (hbpSuperusers.indexOf userid) == -1
            msg.send "Sorry #{user.givenName}, ask an admin to do it for you"
            return
        else
          input = escape(msg.match[1]).trim()
          if parseInt input
            component = components[parseInt(input)-1]
          else
            for c in components
              if c.name == input
                component = c

          if !component
            msg.send "I don't know component #{input}"
            return

          auth = process.env.HUBOT_HBP_CI_USERNAME + ':' + process.env.HUBOT_HBP_CI_USER_TOKEN
          authHeaders = { authorization: 'Basic ' + new Buffer(auth).toString('base64') }

          # get next build number
          http({
            url: "#{ciUrl}/platform.#{component.name}/api/json",
            headers: authHeaders,
            json: true
          }).then (result) ->
            http({
              method: 'POST'
              url: "#{ciUrl}/platform.#{component.name}/build",
              qs: {
                token: process.env.HUBOT_HBP_CI_BUILD_TOKEN
              },
              headers: authHeaders,
              form: {
                json: JSON.stringify({ parameter: component.params })
              }
            })
            .then (resp) ->
                    msg.send "Build is in the queue! I'll keep you posted..."
                    started = false
                    intervalId = setInterval ->
                      http({
                        url: "#{ciUrl}/platform.#{component.name}/#{result.nextBuildNumber}/api/json"
                        headers: authHeaders,
                        json: true
                      }).then (resp) ->
                                if !started
                                  msg.send "build started: [#{result.nextBuildNumber}](#{ciUrl}/platform.#{component.name}/#{result.nextBuildNumber}/console)" +
                                    " I'll let you know when it's done..."
                                  started = true
                                else if resp.result
                                  msg.send "Build #{component.name}/#{result.nextBuildNumber} completed: #{resp.result}"
                                  clearInterval(intervalId)
                              ,(err) ->
                                console.log 'job #{component.name}/#{result.nextBuildNumber} still queuing'

                    , 10000
                  ,(err) ->
                    msg.send "Ops, something went wrong :("



  robot.respond /release$/i, (msg) ->
      msg.send 'tell me what you want to release: ' + (components.map (x, i) -> '\n\n' + (i+1) + ') ' + x.name).join()

  # ########################
  # default bot answer
  robot.catchAll (msg) ->
    if msg.message.text
      msg.send "what do you mean by '#{msg.message.text}'? I'm just a Bluesky hubot!"
