# Direct VideoToolbox diagnostic

`make native-video-probe` builds the native decoder Client and tests three existing
60-frame fixtures. Prepare fixtures first with `make video-probe`. To exercise a
longer local file:

```sh
VIDEO_FILE='/absolute/path/to/fixture.mp4' make native-video-probe
CN_VIDEO_RESTART=1 make native-video-probe
make test-video-state
swift build --target Video
```

The binary links Apple frameworks only. AVAssetReader provides compressed samples
with `alwaysCopiesSampleData = NO`; it skips empty edit-boundary markers. The shell
wrapper uses stock FFmpeg solely to remux an `hev1` fixture into Apple's supported
`hvc1` sample entry, without re-encoding. This is file preparation, outside the live
path. No patched FFmpeg is required or retained in the source tree.

The decoder requires and verifies hardware acceleration, enables real-time decode,
and requests Metal-compatible IOSurface output. It retains the original compressed
CMSampleBuffer through its asynchronous callback. The caller immediately releases
its reference after submission. It never extracts RBSP, flattens a CMBlockBuffer,
rewrites NAL payloads or transfers decoded pixels through CPU memory.

At most four decode submissions are outstanding. Full capacity returns WouldBlock;
it does not sleep, allocate an overflow queue or discard compressed reference frames.
Only this offline harness drains a batch and retries. A live receiver must implement
bounded admission/recovery separately. Temporal-processing delay is not enabled.
B-frame presentation ordering, live source timestamps and audio sync are not solved
by that flag and remain integration work.

The worker serializes configure, submit, drain and stop. VideoToolbox invokes output
on its callback thread, with a borrowed surface which the GPU consumer retains.
Callers must explicitly stop the Client on the owner queue and never stop it from
an output callback. Stop invalidates output admission, waits for callbacks and then
invalidates the session; never call the blocking teardown on the UI/network thread.
A callback already executing can finish during stop, but none survives stop's return.
The independent state machine is protected with a mutex inside the adapter.

| Current phase | Operation | Result |
| --- | --- | --- |
| Idle/stopped | Successful configure | Running, new generation |
| Running | Submit with free slot | Reserve unique ticket |
| Running | Submit when full | WouldBlock, no mutation |
| Running | Stop | Draining, no new admission/output |
| Draining | Complete outstanding ticket | Release that slot |
| Draining, no tickets | Finish stop | Stopped |
| Any | Stale/duplicate completion | Ignored |

Configuration errors leave no active session. Submission errors release their ticket
and return Failed; they do not trigger retries or software fallback. Callers choose
stop/reconfiguration or codec-aware recovery. Frame callback errors are explicit.

Metal checks both plane textures reference the decoded IOSurface, converts SDR/PQ
into private RGBA16Float outputs and retains textures/pixel buffers until GPU
completion. Two output slots bound GPU work. Its waits and callback serialization
are diagnostic policies, not the future live presentation implementation.

The verified copy boundary is application submission of the existing sample and
sharing decoded surfaces with Metal. AVAssetReader, VideoToolbox internals and network
assembly are not certified end-to-end zero-copy.

`CN_VIDEO_ANNEXB=1 make native-video-probe` exercises the owned Annex-B adapter.
The fixture reader copies packet bytes solely to prepare simulated Annex-B input;
the adapter builds segmented Core Media blocks without copying the resulting NAL
payloads. This is not a live Chiaki test or a zero-copy claim for fixture preparation.
