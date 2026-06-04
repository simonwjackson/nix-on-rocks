# devices/rk3566

SoC-bound data and device-policy defaults for Rockchip RK3566
  handhelds.## Current target

  - Anbernic
  RG353M
  (`rg353m`)
  - ROCKNIX host family: RK3566 Generic / Anbernic RGXX3
- Boot shape: U-Boot + extlinux SD-card image, not SM8550 fastboot/ABL

## What belongs here

- RK3566-specific package inputs once they exist, such as RK817 audio policy or
Mali/Panfrost-tuned runtime data.
- SoC-level notes that are shared by RG353-family products.
- Evaluation-only placeholders needed to keep RK3566 profile contracts honest
before hardware arrives.

## What does not belong here

- Hostname and product profile selection: those live in
`guest/profiles/devices/rg353m.nix`.
- ROCKNIX kernel/U-Boot support already carried by upstream ROCKNIX under
`work/rocknix/projects/ROCKNIX/devices/RK3566/`.
- Destructive eMMC procedures. First bring-up stays SD-card only until hardware
evidence and an explicit later decision approve anything else.

## Known constraints before hardware arrives

- The actual RG353M model and compatible strings must be captured from
`/proc/device-tree` before final by-compatible selection is wired.
- RG353M may reuse the RG353P DTB through U-Boot runtime fixups.
- RK817 audio config is not implemented here yet; the initial profile uses an
evaluation-only empty UCM directory so static contracts can prove RK3566 does
not accidentally consume the SM8550 AYN Odin UCM package.
- Display connector, input event names, and WiFi/Bluetooth details remain
evidence-driven follow-up work.
