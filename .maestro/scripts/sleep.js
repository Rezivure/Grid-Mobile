// Sleep for DURATION_MS milliseconds
// Usage in flow: runScript with env DURATION_MS
var ms = parseInt(DURATION_MS || '3000')
java.lang.Thread.sleep(ms)
