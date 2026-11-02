# Stock FFmpeg video surface diagnostic

The selected live backend is now direct VideoToolbox. This older probe remains
a fixture generator and comparison tool; see ../NativeVideoProbe/README.md.

Run `make video-probe` from the repository root. Requires macOS, Metal,
the installed Xcode compiler/SDK and pkg-config. The probe links the same pinned
FFmpeg libraries as the app. Fixture generation additionally needs an FFmpeg CLI
with libx264/libx265 encoders; `VIDEO_FILE` uses an existing fixture without that CLI. No Xcode window or PlayStation account is used.
This is separate from `make test` because it requires a GPU and VideoToolbox.

The script generates two 60-frame synthetic 640x360 fixtures: 8-bit H.264 and
10-bit HEVC. It decodes using FFmpeg's VideoToolbox backend, rejects software
AVFrame output, checks IOSurface identity for both imported Metal planes and
runs a compute shader into private RGBA16Float textures. At most two command
buffers are in flight. Each output slot is recycled only after its completion
handler releases its AVFrame and CVMetalTexture leases. Slot/drain waits have a
ten-second deadline. GPU failure, missing surfaces, unexpected pixel format or
wrong frame count fail the run. No decoded pixel buffer is CPU-mapped or copied.

The active shader now converts SDR/PQ input to extended-linear RGB; see the
PQ/HDR section below for the tested scope and remaining presentation work.
The HEVC backend requesting hardware acceleration is not by itself a measurement
of the physical decoder selected; capability reporting still needs that proof.
No throughput/latency claim follows from these small offline fixtures.

This executable intentionally diagnoses stock FFmpeg and is not linked into the
app. Its compressed-input path does NOT meet the strict zero-copy requirement.
Do not promote it to production without resolving
those copies. Demuxed fixture packets are a test source, not a proposed
replacement for Chiaki's network ownership contract.

## PQ/HDR samples

The current shader is `colour.metal`: it handles limited/full-range bi-planar
8/10-bit BT.709 and BT.2020 non-constant-luminance input, converts PQ into linear
BT.709 at an explicit 100-nit reference white, and preserves EDR values above 1.
It rejects missing/mismatched metadata and HLG. The older `planes.metal` remains
only as a raw-channel inspection shader, not the active renderer.

`make video-probe` now also generates a 60-frame BT.2020/PQ neutral ramp and runs
numeric GPU tests at black, 100, 1000 and 10000 nits. Test-only shared-buffer
readback validates that math, including a baseline luminance-preserving Reinhard
SDR mapping. This readback is outside playback. These are limited numeric checks,
not certification of gamut mapping, chroma siting, HDR10+ or final display colour.
The offscreen fixture path outputs extended-linear colour; a CAMetalLayer window,
EDR-headroom handling and upscaling remain to be implemented.

For a public YouTube PQ sample:

```sh
make video-deps
VIDEO_URL='https://www.youtube.com/watch?v=VIDEO_ID' make video-fixture
VIDEO_FILE='/absolute/path/printed/by/importer/fixture-hevc-pq.mp4' make video-probe
```

The importer requests the first 20 seconds of an HDR rendition, without loading
browser cookies or personal downloader configuration. It checks the downloaded
stream for PQ, BT.2020 and 10/12-bit 4:2:0; SDR, HLG and missing metadata fail.
YouTube availability/extraction may fail; the tool does not substitute SDR.
A requested range may include additional boundary frames due to keyframe cuts.

VP9/AV1 samples are transcoded offline into HEVC Main10, with the original retained
and provenance recorded under `.build/video-fixtures`. This is explicitly lossy
fixture preparation, not the zero-copy playback path. It does not establish that
all mastering or dynamic metadata survived conversion.
Synthetic fixtures and GPU checks run without either or an HDR monitor. Visual
HDR validation still requires a suitable display.
