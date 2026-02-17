// Join a user to a room
// Env: USER, ROOM_ID, MAESTRO_DIR
var cmd = 'cd ' + MAESTRO_DIR + '/helpers && ./api_join_room.sh ' + USER + ' "' + ROOM_ID + '"'
var process = java.lang.Runtime.getRuntime().exec(['/bin/bash', '-c', cmd])
process.waitFor()

var reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))
var errReader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))
var result = '', errResult = '', line
while ((line = reader.readLine()) != null) result += line + '\n'
while ((line = errReader.readLine()) != null) errResult += line + '\n'

console.log('api_join_room: ' + result.trim())
if (errResult.trim()) console.log('STDERR: ' + errResult.trim())
if (process.exitValue() !== 0) throw new Error('api_join_room failed: ' + errResult.trim())
