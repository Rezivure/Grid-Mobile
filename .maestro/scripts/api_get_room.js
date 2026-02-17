// Get first joined room for a user
// Env: USER, MAESTRO_DIR
var cmd = 'cd ' + MAESTRO_DIR + '/helpers && TOKEN=$(./api_login.sh ' + USER + ') && curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8008/_matrix/client/r0/joined_rooms" | jq -r ".joined_rooms[0]"'
var process = java.lang.Runtime.getRuntime().exec(['/bin/bash', '-c', cmd])
process.waitFor()

var reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))
var errReader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))
var result = '', errResult = '', line
while ((line = reader.readLine()) != null) result += line + '\n'
while ((line = errReader.readLine()) != null) errResult += line + '\n'

if (process.exitValue() !== 0) throw new Error('api_get_room failed: ' + errResult.trim())
output.roomId = result.trim()
console.log('Room ID for ' + USER + ': ' + output.roomId)
