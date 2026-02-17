// Leave a room
var HOMESERVER = 'http://localhost:8008'

var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', user: USER, password: 'testpass123' })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + USER)

var leaveResp = http.post(
    HOMESERVER + '/_matrix/client/r0/rooms/' + encodeURIComponent(ROOM_ID) + '/leave',
    {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
        },
        body: '{}'
    }
)

if (!leaveResp.ok) throw new Error('Leave room failed for ' + USER + ': ' + leaveResp.body)
console.log(USER + ' left room ' + ROOM_ID)
