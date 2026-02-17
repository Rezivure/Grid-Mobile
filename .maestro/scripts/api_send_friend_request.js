// Send friend request from FROM_USER to TO_USER via Matrix API
// Uses Maestro's built-in http API
var HOMESERVER = 'http://localhost:8008'

// Login as sender
var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        type: 'm.login.password',
        user: FROM_USER,
        password: 'testpass123'
    })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + FROM_USER + ': ' + loginResp.body)

// Get TO_USER's full Matrix ID
var toUserId = '@' + TO_USER + ':localhost'

// Create DM room and invite
var roomResp = http.post(HOMESERVER + '/_matrix/client/r0/createRoom', {
    headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + token
    },
    body: JSON.stringify({
        is_direct: true,
        preset: 'trusted_private_chat',
        invite: [toUserId]
    })
})
var roomId = json(roomResp.body).room_id
if (!roomId) throw new Error('Create room failed: ' + roomResp.body)

output.roomId = roomId
console.log('Friend request sent from ' + FROM_USER + ' to ' + TO_USER + ' in room ' + roomId)
