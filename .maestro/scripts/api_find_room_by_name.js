// Find a room by name pattern for a user
// Env: USER, ROOM_NAME
var HOMESERVER = 'http://localhost:8008'

var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', user: USER, password: 'testpass123' })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + USER)

// Get joined rooms
var roomsResp = http.get(HOMESERVER + '/_matrix/client/r0/joined_rooms', {
    headers: { 'Authorization': 'Bearer ' + token }
})
var rooms = json(roomsResp.body).joined_rooms
if (!rooms || rooms.length === 0) throw new Error('No rooms found for ' + USER)

// Check each room's state for the name
var foundRoomId = null
for (var i = rooms.length - 1; i >= 0; i--) {
    var stateResp = http.get(
        HOMESERVER + '/_matrix/client/r0/rooms/' + encodeURIComponent(rooms[i]) + '/state/m.room.name',
        { headers: { 'Authorization': 'Bearer ' + token } }
    )
    if (stateResp.ok) {
        var name = json(stateResp.body).name
        if (name && name.indexOf(ROOM_NAME) !== -1) {
            foundRoomId = rooms[i]
            console.log('Found room "' + name + '": ' + foundRoomId)
            break
        }
    }
}

if (!foundRoomId) throw new Error('No room found matching "' + ROOM_NAME + '" for ' + USER)
output.roomId = foundRoomId
