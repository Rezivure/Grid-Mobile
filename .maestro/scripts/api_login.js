// Login a user and store token in output
var HOMESERVER = 'http://localhost:8008'
var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        type: 'm.login.password',
        user: USER,
        password: 'testpass123'
    })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + USER + ': ' + loginResp.body)
output.token = token
output.userId = '@' + USER + ':localhost'
console.log('Logged in as ' + USER)
