# Layer 14 network module: NetworkManager + iwd own wlan0 from the guest.
#
# Tier C confirmed:
#   - guest and host already share root netns (Layer 14 wants this)
#   - veth+NAT pattern is reserved for side-by-side experimental guests,
#     not main-space
#   - kernel lacks ip_tables.ko; firewall MUST be nftables
#
# Tier E1/E5 surfaced repeated DNS clobber under load when host
# resolvconf wrote to a host-bound /etc/resolv.conf. Layer 14 unit
# does not bind /etc/resolv.conf; this module also disables resolvconf
# inside the guest and lets NetworkManager manage DNS directly so
# nothing else can clobber it.
#
# Tailscale is guest-owned in the minimal-host model. The host keeps only
# enough network substrate for recovery/SSH; the NixOS guest owns the
# product/development tailnet identity. The nspawn unit binds /dev/net/tun
# and the guest runs in the shared netns, so tailscaled can create the
# tailnet interface from inside the guest while preserving host minimalism.
{ config, pkgs, ... }:

{
  networking.networkmanager = {
    enable = true;
    # Keep the wireless control plane in the guest. ROCKNIX used iwd for the
    # SM8550 Wi-Fi PHY; using NetworkManager's iwd backend lets the guest own
    # nl80211/rfkill/auth instead of depending on a host iwd daemon.
    wifi.backend = "iwd";
    dns = "default";
  };

  # Firewall + nftables disabled inside the nspawn guest. systemd-nspawn
  # without --capability=CAP_NET_ADMIN/CAP_NET_RAW (and without the host
  # exposing nf_tables.ko caps cleanly) makes nftables.service abort with
  # "netlink: Error: cache initialization failed: Operation not permitted"
  # on every activation, leaving a permanently-failed unit.
  #
  # The trust boundary lives at the host (rocknix-graphical.target wires
  # the guest, the host enforces network policy). The guest doesn't need
  # its own firewall ruleset under the shared-netns Layer-14 model.
  #
  # Validated on Thor 2026-05-08: nftables.service failed every guest
  # boot under enable=true; with enable=false, no failed units (apart
  # from independently-known sshd.socket port-conflict).
  networking.firewall.enable = false;
  networking.nftables.enable = false;

  networking.resolvconf.enable = false;

  services.resolved.enable = false;

  # The rootfs can carry a stale systemd-resolved stub resolv.conf from
  # earlier experiments. Point /etc/resolv.conf at NetworkManager's real
  # upstream resolver file so tailscaled does not try to talk to a disabled
  # systemd-resolved service.
  environment.etc."resolv.conf".source = "/run/NetworkManager/no-stub-resolv.conf";

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraSetFlags = [
      "--accept-dns=false"
      "--netfilter-mode=off"
      "--hostname=${config.networking.hostName}"
    ];
  };

  # systemd-nspawn gives interactive root enough capability to create a tun
  # device, but systemd-launched services inside the container do not inherit
  # those caps ambiently. tailscaled needs them to create tailscale0 and open
  # its UDP socket from the guest-owned network namespace.
  systemd.services.tailscaled.serviceConfig.AmbientCapabilities = [
    "CAP_NET_ADMIN"
    "CAP_NET_RAW"
  ];

  environment.systemPackages = with pkgs; [
    iw
    nftables
    iproute2
    networkmanager
    iwd
    tailscale
  ];
}
