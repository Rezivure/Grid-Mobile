// Get first joined room for a user
var HOMESERVER = 'http://localhost:8008'

// Login
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

output.roomId = rooms[0]
console.log('Room for ' + USER + ': ' + output.roomId)
