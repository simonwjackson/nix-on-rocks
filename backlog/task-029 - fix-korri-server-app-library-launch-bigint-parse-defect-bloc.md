---
id: task-029
title: Fix korri-server app.library.launch BigInt parse defect blocking sessiond launch
status: To Do
priority: high
labels:
  - rg353m
  - korri-server
  - rpc
  - launch
  - sessiond
  - bug
  - cross-repo
created: 2026-06-07
source: se-debug
---

# Fix korri-server app.library.launch BigInt parse defect blocking sessiond launch

## Why it matters

This is the single thing standing between the RG353M and a non-freezing, product-path gamescope launch. We proved (task-028) that gamescope only renders reliably on Mali-G52 when run as the primary DRM compositor, and that the supported way to get there is the Korri sessiond home→game display transition (which hides the Electrobun webview and hands gamescope the output). That transition is invoked through korri-server's `app.library.launch` RPC — which currently fails for every payload with a Defect, so we were forced into ad-hoc manual `gamescope -- retroarch` launches that hit the nested-compositor freeze. Until this RPC works, there is no clean product launch path on RG353M (and likely none on any device, since it's payload-independent).

## Related

- `../korri/product/apps/portal/api/library`
- `../korri (korri-server.js launch handler, minified)`
- `backlog/task-028 - enable-gamescope-on-rg353m-mali-g52-rk3566.md`
- `docs/solutions/integration-issues/gamescope-on-mali-g52-panvk-rk3566-2026-06-06.md`

## Notes

REPO: this bug lives in the **korri** repo (../korri), not nix-on-rocks. Tracked here because it blocks the RG353M gamescope story (task-028).

SYMPTOM (exact): POST to the RPC endpoint returns a Defect, independent of payload:
  curl -s -X POST -H 'content-type: application/json' \
    --data '{"_tag":"Request","id":"L1","tag":"app.library.launch","payload":{"id":"super-mario-advance"}}' \
    http://127.0.0.1:3001/api/rpc
  -> [{"_tag":"Defect","defect":{"name":"SyntaxError","message":"Failed to parse String to BigInt"}}]

KEY FACTS ESTABLISHED:
- Payload-independent: reproduced with {id}, {id,presetId:null}, {id,presetId:"unpatched",userId:"0"}, {id,userId:"1"}. Same defect every time.
- NOT an RPC-framing problem: `app.library.list` works perfectly with the SAME Effect-RPC frame shape ({"_tag":"Request","id":"<nonempty-string>","tag":"...","payload":{}}). Note the RPC `id` must be a NON-EMPTY string (numeric id -> "Request.id must be a non-empty string").
- The message "Failed to parse String to BigInt" is Effect Schema's BigIntFromString decode error (grep of korri-server.js shows BigIntFromString = make28(bigIntString...)). Something in the launch path decodes a string->BigInt and gets an empty/invalid string.
- The launch handler region (korri-server.js ~offset 2.69-2.70M) checks `snap.users.has(inputs.userId)` and fails `new UserNotFound` if userId set+missing. LaunchLibraryPayload schema = { id: String, source?: EntrySource, userId?: String, presetId?: String|Null, override?: EphemeralOverride }.
- No on-disk stats/user files exist under /var/lib/korri-server except library.yaml (so it's not a corrupt persisted BigInt file) — likely a runtime-constructed value (launchId / timestamp / span / playtime) decoded via BigIntFromString with an empty input.
- The server is a minified bun bundle: /nix/store/xbj06g3mhhh38wyk6ig210xwnaxmn2gs-korri-server-1.0.0/share/korri-server/korri-server.js. Source is in ../korri (product/apps/portal/api/library/*.rpc.ts and the launch handler).

HOW TO REPRODUCE ON DEVICE:
- RG353M guest reachable via: ssh yuki -> ssh -p 2222 root@192.168.1.140 (UserKnownHostsFile=/tmp/rg353m-guest-ready-known_hosts).
- korri-server listens on 0.0.0.0:3001 (RPC at /api/rpc). sessiond on 127.0.0.1:3003 (auth header `x-korri-sessiond-token: $(cat /run/korri-sessiond/token)`; endpoints /control/start, /launch {spec}, /managed-launch {spec,launchId,lifecycle?,wait?}).
- journalctl -u korri-server did not surface a stack; run the bun server with a debug/stacktrace build or add logging around the BigIntFromString decode in the launch path to localize the field.

SUGGESTED FIX APPROACH:
1. In ../korri, find the app.library.launch handler + the LaunchLibraryResponse/managed-launch spec construction; grep for BigIntFromString / BigInt usage in the launch path (launchId, timestamps, playtime/stats).
2. Identify which field gets an empty string and either default it or make the schema tolerant.
3. Add a unit/integration test that drives app.library.launch with a minimal payload and asserts a non-Defect response.
4. Then verify on RG353M: app.library.launch -> sessiond managed-launch -> gamescope foregrounded as the session surface (validates the home->game transition that avoids the nested freeze).

DEPLOY / REBUILD LANE: **Payload re-render.** The fix is in the ../korri repo (korri-server bun bundle). It reaches the device by rebuilding the Korri payload and `scripts/render-product-payload` + redeploying the payload to the guest — **fast**, no SD reflash and no guest-system rebuild. A **full image rebuild** is only needed if a fresh seeded baseline is wanted. Pairs with task-028's payload re-render (same lane), so both can ship together.
