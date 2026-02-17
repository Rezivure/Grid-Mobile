// Sleep for DURATION_MS milliseconds using a busy-wait loop
// (Maestro's GraalJS has no Thread.sleep or setTimeout)
var end = Date.now() + parseInt(DURATION_MS)
while (Date.now() < end) {
    // busy wait
}
