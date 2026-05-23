# Plan C quick spike — direct V4L2 + dma-buf export on Sobo — 2026-05-23

## Question

If we bypass FFmpeg's `v4l2_m2m` wrapper, can the SM8550 iris decoder provide capture buffers that we can export as dma-bufs for a true zero-copy path?

## Short answer

Partially yes:

- V4L2 stateful decoder setup and `VIDIOC_EXPBUF` on CAPTURE buffers works.
- EGL import of that exported NV12 dma-buf is not yet proven.
- Surfaced conclusion: Plan C is feasible at the V4L2 buffer-export layer, but still needs a real renderer/import proof and then a large queue/lifecycle implementation.

## Probe 1: V4L2 CAPTURE `VIDIOC_EXPBUF`

A small C probe was compiled on Fuji and run on Sobo. It:

1. opened `/dev/video0`,
2. queried formats,
3. set OUTPUT to HEVC 1280x720,
4. set CAPTURE to NV12 1280x720,
5. requested CAPTURE MMAP buffers,
6. called `VIDIOC_EXPBUF` on each capture buffer.

Output:

```text
opened /dev/video0 fd=3
driver=iris_driver card=Iris Decoder bus=platform:aa00000.video-codec caps=0x84204000 dev_caps=0x04204000

formats OUTPUT_MPLANE:
  [0] H264 0x34363248 H.264 flags=0x9
  [1] HEVC 0x43564548 HEVC flags=0x9
  [2] VP90 0x30395056 VP9 flags=0x9
  [3] AV01 0x31305641 AV1 OBU Stream flags=0x9

formats CAPTURE_MPLANE:
  [0] NV12 0x3231564e Y/UV 4:2:0 flags=0x0
  [1] Q08C 0x43383051 QCOM Compressed 8-bit Format flags=0x1
S_FMT OUTPUT HEVC accepted: HEVC 1280x736 planes=1
  plane0 sizeimage=7077888 bytesperline=0
S_FMT CAPTURE NV12 accepted: NV12 1280x736 planes=1
  plane0 sizeimage=1413120 bytesperline=1280
REQBUFS CAPTURE returned count=4
EXPBUF index=0 plane=0 OK dma_fd=4
EXPBUF index=1 plane=0 OK dma_fd=4
EXPBUF index=2 plane=0 OK dma_fd=4
EXPBUF index=3 plane=0 OK dma_fd=4
```

Interpretation:

- iris accepts the direct stateful-decoder setup.
- capture is aligned to 1280x736, not the visible 1280x720.
- NV12 is single-V4L2-plane / two-image-plane layout: Y at offset 0, UV likely at `stride * aligned_height`.
- `VIDIOC_EXPBUF` works on CAPTURE buffers, so the kernel side is not a dead end.

## Probe 2: surfaceless EGL import of exported NV12 dma-buf

A second probe exported one capture buffer and tried to import it through surfaceless EGL using:

- `EGL_LINUX_DMA_BUF_EXT`
- `DRM_FORMAT_NV12`
- plane 0 fd/offset/pitch = `fd, 0, 1280`
- plane 1 fd/offset/pitch = `fd, 1280*736, 1280`

Output:

```text
capture accepted: NV12 1280x736 planes=1 size=1413120 stride=1280
exported dma-buf fd=4
EGL 1.5 initialized
EGL_EXT_image_dma_buf_import=yes modifiers=yes
eglCreateImageKHR(NV12 dmabuf) failed err=0x3003 w=1280 h=736 stride=1280 uv_off=942080
```

`0x3003` is `EGL_BAD_ALLOC`.

Interpretation:

- dma-buf import extension is available.
- This particular surfaceless import failed.
- The failure is not conclusive for the app path because surfaceless EGL may select a different device/context than the Wayland/SDL compositor path. It also imported an allocated-but-never-decoded capture buffer, so driver requirements around buffer state may differ.

## Probe 3: SDL/Wayland EGL import attempt

A third probe attempted to create an SDL Wayland GL context and import the same exported dma-buf into `eglGetCurrentDisplay()`.

It crashed with SIGSEGV after exporting the dma-buf, before printing SDL/EGL context details:

```text
capture NV12 1280x736 stride=1280 uv_off=942080 size=1413120
exported dma-buf fd=4
Segmentation fault (rc=139)
```

Interpretation:

- Inconclusive. This is likely a throwaway-probe issue (dynamic library/context setup) rather than evidence against Plan C.
- If Plan C proceeds, build the import probe inside the moonlight-embedded scratch tree and reuse the same SDL/EGL initialization code as the platform, rather than a standalone ad-hoc binary.

## Plan C implementation sketch

A true zero-copy implementation would need to own the stateful V4L2 lifecycle directly:

1. Open `/dev/video0`.
2. Set OUTPUT format (`H264` / `HEVC`) and CAPTURE format (`NV12` or `Q08C`).
3. Allocate OUTPUT buffers for compressed bitstream packets.
4. Allocate CAPTURE buffers with MMAP or DMABUF-capable memory.
5. Export CAPTURE buffers with `VIDIOC_EXPBUF` and keep fd/lifetime bookkeeping.
6. Queue/dequeue OUTPUT and CAPTURE buffers.
7. Handle `V4L2_EVENT_SOURCE_CHANGE` and resolution renegotiation.
8. Convert each dequeued CAPTURE buffer into renderer input:
   - EGL import path if import works,
   - or compositor-native dma-buf path if targeting Wayland protocols directly.
9. Handle buffer ownership so a CAPTURE buffer is not re-queued until the GPU/compositor is done sampling it.

## Decision

Plan C is not blocked at the V4L2 export layer. The blocker/risk is renderer import + lifecycle complexity.

Given the accepted SDL NV12 path already reduces Moonlight CPU from ~49% to ~13% on Sobo, Plan C should remain a future optimization/research track unless true zero-copy becomes a product requirement.
