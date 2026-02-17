// Leave all rooms for a list of test users to reset state
// Env: USERS (comma-separated, e.g. "testuser1,testuser2,testuser3")
var HOMESERVER = 'http://localhost:8008'
var users = USERS.split(',')

for (var u = 0; u < users.length; u++) {
    var user = users[u].trim()
    var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'm.login.password', user: user, password: 'testpass123' })
    })
    var token = json(loginResp.body).access_token
    if (!token) { console.log('Login failed for ' + user + ', skipping'); continue }

    var roomsResp = http.get(HOMESERVER + '/_matrix/client/r0/joined_rooms', {
        headers: { 'Authorization': 'Bearer ' + token }
    })
    var rooms = json(roomsResp.body).joined_rooms || []
    console.log(user + ' has ' + rooms.length + ' rooms')

    for (var i = 0; i < rooms.length; i++) {
        http.post(HOMESERVER + '/_matrix/client/r0/rooms/' + encodeURIComponent(rooms[i]) + '/leave', {
            headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
            body: '{}'
        })
    }
    console.log(user + ': left ' + rooms.length + ' rooms')
}
