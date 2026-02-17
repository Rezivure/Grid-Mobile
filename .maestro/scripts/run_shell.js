// Generic shell command runner for Maestro
// Usage: runScript with env SHELL_CMD set to the command to run
var process = java.lang.Runtime.getRuntime().exec(['/bin/bash', '-c', SHELL_CMD])
process.waitFor()

var reader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream()))
var errReader = new java.io.BufferedReader(new java.io.InputStreamReader(process.getErrorStream()))
var result = ''
var errResult = ''
var line

while ((line = reader.readLine()) != null) {
    result += line + '\n'
}
while ((line = errReader.readLine()) != null) {
    errResult += line + '\n'
}

if (result.trim()) {
    output.shellResult = result.trim()
    console.log('STDOUT: ' + result.trim())
}
if (errResult.trim()) {
    console.log('STDERR: ' + errResult.trim())
}

var exitCode = process.exitValue()
if (exitCode !== 0) {
    console.log('Exit code: ' + exitCode)
    throw new Error('Shell command failed with exit code ' + exitCode + ': ' + errResult.trim())
}
