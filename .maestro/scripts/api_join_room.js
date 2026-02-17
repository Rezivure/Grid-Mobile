// Join a user to a room
var HOMESERVER = 'http://localhost:8008'

var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', user: USER, password: 'testpass123' })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + USER)

var joinResp = http.post(
    HOMESERVER + '/_matrix/client/r0/join/' + encodeURIComponent(ROOM_ID),
    {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
        },
        body: '{}'
    }
)

if (!joinResp.ok) throw new Error('Join room failed for ' + USER + ': ' + joinResp.body)
console.log(USER + ' joined room ' + ROOM_ID)
