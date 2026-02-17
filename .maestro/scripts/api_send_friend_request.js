// Send friend request from FROM_USER to TO_USER via Matrix API
var cmd = 'cd ' + MAESTRO_DIR + '/helpers && ./api_send_friend_request.sh ' + FROM_USER + ' ' + TO_USER
var process = java.lang.Runtime.getRuntime().exec(['/bin/bash', '-c', cmd])
process.waitFor()

var reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))
var errReader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))
var result = '', errResult = '', line
while ((line = reader.readLine()) != null) result += line + '\n'
while ((line = errReader.readLine()) != null) errResult += line + '\n'

console.log('api_send_friend_request: ' + result.trim())
if (errResult.trim()) console.log('STDERR: ' + errResult.trim())
if (process.exitValue() !== 0) throw new Error('api_send_friend_request failed: ' + errResult.trim())
output.roomId = result.trim()
