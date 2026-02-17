// Invite a user to a room (as the room creator/admin)
// Env: ADMIN_USER, INVITE_USER, ROOM_ID
var HOMESERVER = 'http://localhost:8008'

var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', user: ADMIN_USER, password: 'testpass123' })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + ADMIN_USER)

var inviteResp = http.post(
    HOMESERVER + '/_matrix/client/r0/rooms/' + encodeURIComponent(ROOM_ID) + '/invite',
    {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
        },
        body: JSON.stringify({ user_id: '@' + INVITE_USER + ':localhost' })
    }
)

if (!inviteResp.ok) throw new Error('Invite failed: ' + inviteResp.body)
console.log('Invited ' + INVITE_USER + ' to room ' + ROOM_ID)
