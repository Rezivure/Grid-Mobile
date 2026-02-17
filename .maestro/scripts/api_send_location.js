// Send location update for a user in a room
var HOMESERVER = 'http://localhost:8008'

// Login
var loginResp = http.post(HOMESERVER + '/_matrix/client/r0/login', {
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ type: 'm.login.password', user: USER, password: 'testpass123' })
})
var token = json(loginResp.body).access_token
if (!token) throw new Error('Login failed for ' + USER)

// Send location as m.room.message with geo_uri
var txnId = 'loc_' + Date.now()
var geoUri = 'geo:' + LAT + ',' + LON

var sendResp = http.put(
    HOMESERVER + '/_matrix/client/r0/rooms/' + encodeURIComponent(ROOM_ID) + '/send/m.room.message/' + txnId,
    {
        headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ' + token
        },
        body: JSON.stringify({
            msgtype: 'm.location',
            body: 'Location: ' + LAT + ', ' + LON,
            geo_uri: geoUri
        })
    }
)

if (!sendResp.ok) throw new Error('Send location failed: ' + sendResp.body)
console.log('Location sent by ' + USER + ': ' + geoUri)
