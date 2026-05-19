# Layer 14 main-space profile.
#
# Composes:
#   - base (minimal NixOS container)
#   - tools (CLI utilities for the developer)
#   - ssh (Layer 12 opt-in SSH on port 2222)
#   - display (sway + Mesa freedreno/turnip)
#   - audio (pipewire + wireplumber + bluez + dbus)
#   - input (guest-owned InputPlumber + SM8550 maps)
#   - network (NetworkManager + nftables firewall, no resolvconf)
#
# Used by THIN_HOST=yes builds via nixosConfigurations.rocknix-guest-main-space
# in flake.nix.
#
# Combined-profile note (2026-05-11): main-space now bakes the interactive
# bits formerly only available in profiles/dev-env.nix -- a bottom swaybar
# with clock/battery, Home-prefixed sway chord bindings (Home then Return
# for foot, Home then d for fuzzel, Home then g for games-launcher,
# workspaces 1-9, focus/move/layout), and `exec foot` so a cold boot lands
# the user on something interactive
# instead of a black screen. The audio/Steam/Cemu module composition is
# unchanged.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Status line script for swaybar. Lives as a separate file rather
  # than inline in the bar block because sway's config parser strips
  # shell quoting from `status_command`, which silently mangles any
  # multi-token script. As an absolute path to a writeShellScript
  # output, it survives sway parsing untouched and runs under the same
  # bash the kiosk unit adds to its PATH.
  sm8550 = config.rocknix.sm8550;

  swayBarStatus = pkgs.writeShellScript "sway-bar-status" ''
    while true; do
      cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null \
         || cat /sys/class/power_supply/BAT*/capacity 2>/dev/null \
         | head -1)
      clock=$(date '+%H:%M')
      printf '%s | bat %s%%\n' "$clock" "''${cap:-?}"
      sleep 5
    done
  '';

  portalBootstrap = pkgs.writeShellScript "rocknix-portal-bootstrap" ''
    set -u
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/0}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-sway}"
    if [ -z "''${SWAYSOCK:-}" ]; then
      SWAYSOCK=$(${pkgs.coreutils}/bin/ls "$XDG_RUNTIME_DIR"/sway-ipc.0.*.sock 2>/dev/null | ${pkgs.coreutils}/bin/head -1 || true)
      export SWAYSOCK
    fi

    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP \
      >/dev/null 2>&1 || true

    ${pkgs.coreutils}/bin/timeout 3s ${pkgs.systemd}/bin/systemctl --user reset-failed \
      xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-document-portal.service \
      >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/timeout 3s ${pkgs.systemd}/bin/systemctl --user start \
      xdg-desktop-portal-gtk.service xdg-desktop-portal.service \
      >/dev/null 2>&1 || true
  '';
in

{
  imports = [
    ../modules/base.nix
    ../modules/device.nix
    ../modules/tools.nix
    ../modules/ssh.nix
    ../modules/display.nix
    ../modules/audio.nix
    ../modules/input.nix
    ../modules/network.nix
    ../modules/lid.nix
    ../modules/steam.nix
  ];

  # Layer 14 default hostname: distinguish from the Layer 10b minimal
  # "rocknix-guest" while allowing device profiles to provide stable
  # per-device names for SSH, Tailscale, and journals.
  networking.hostName = lib.mkDefault "rocknix-nix";

  # Tier E2 surfaced tz-data.service 203/EXEC on every switch because
  # ROCKNIX's tz-data unit ExecStart=/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE}
  # and the variable was empty. Setting time.timeZone declaratively here
  # avoids the noise (NixOS owns its own zoneinfo path).
  time.timeZone = "America/New_York";

  # Stop the rate-limited journal-flush noise that fires when the guest's
  # /run is tmpfs and journald can't pre-allocate.
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';

  # Stable root session bus for the kiosk session and FHS-wrapped generic
  # Linux apps such as Steam.  sway's wrapper can create a private dbus socket
  # under /tmp via dbus-run-session, but that breaks FHS private-tmp wrappers:
  # /run/user/0/bus becomes a symlink into a different /tmp.  Owning the bus at
  # /run/user/0/bus keeps it visible through the bind-mounted /run namespace.
  systemd.services.rocknix-session-dbus = {
    description = "ROCKNIX Layer 14 root session D-Bus";
    wantedBy = [ "multi-user.target" ];
    before = [ "rocknix-sway-kiosk.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.dbus}/bin/dbus-daemon --session --address=unix:path=/run/user/0/bus --nofork --nopidfile";
      Restart = "on-failure";
      RestartSec = 3;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Layer 14 first-light autostart wiring (Thor validation 2026-05-08).
  #
  # We do NOT use services.greetd: greetd's PAM stack pulls in
  # pam_systemd.so which fails to dlopen inside nspawn ("failed to map
  # segment from shared object") because nspawn's seccomp/capability
  # profile blocks the mmap pattern PAM modules use. greetd then exits
  # cleanly but never spawns a session.
  #
  # Instead, ship a bare systemd service that runs sway directly.
  # wlroots's seatd backend (built into sway) takes /dev/dri/card0 and
  # /dev/tty1 master without needing PAM or logind sessions.
  #
  # Why no TTYPath / StandardInput=tty / PAMName: live validation on Thor
  # 2026-05-08 showed that the moment systemd is asked to claim a TTY for
  # the unit it tries to run a PAM auth pre-exec step that fails silently
  # inside nspawn (no logind, no pam_systemd) and the unit exits 127
  # before sway is even reached. wlroots's libseat backend acquires its
  # own VT directly from /dev/tty0 / /dev/tty1 (which the host nspawn
  # unit binds in) when sway initialises the DRM session, so there is no
  # need to hand the unit a TTY explicitly.
  systemd.services.rocknix-sway-kiosk = {
    description = "ROCKNIX Layer 14 sway kiosk session";
    wantedBy = [ "multi-user.target" ];
    # Do not order After=multi-user.target here. This service is WantedBy
    # multi-user.target; ordering it after the target lets the target complete
    # without reliably launching the compositor during boot. Order only after
    # the concrete prerequisites it actually needs.
    after = [
      "systemd-user-sessions.service"
      "rocknix-session-dbus.service"
    ];
    requires = [ "rocknix-session-dbus.service" ];

    # sway's wrapper invokes dbus-run-session which spawns dbus-daemon.
    # Without dbus on the unit's PATH the wrapper fails with
    # "dbus-run-session: failed to execute message bus daemon
    # 'dbus-daemon': No such file or directory" before sway is reached.
    #
    # Sway client commands (foot, swaybg, swaylock) inherit sway's PATH;
    # add them here so `swaymsg exec foot` works without requiring the
    # caller to set absolute paths.
    #
    # bashInteractive is required because sway's exec mechanism
    # (both `swaymsg exec` over IPC and `bindsym ... exec ...` keybinds)
    # calls `execlp("sh", "sh", "-c", cmd, NULL)`. Without bash on the
    # unit's PATH that lookup fails with ENOENT and sway logs
    # `[sway/commands/exec_always.c:65] execve failed: No such file or
    # directory` for every exec attempt. The systemd default service
    # PATH on NixOS does not include any shell. Verified live on Thor
    # 2026-05-08: PATH inspection of sway's /proc/<pid>/environ showed
    # only nix store package bin/ dirs, none containing `sh`.
    #
    # Interactive-profile additions (combined main-space):
    #   - fuzzel: launcher invoked by the Home then d chord.
    #   - git: handy for in-session scratch work; matches dev-env parity.
    #   - coreutils: provides `date` and `cat` used by swayBarStatus.
    #   - sway: makes the `swaybar` helper reachable. Sway forks swaybar
    #     via execlp("swaybar", ...), same PATH-lookup mechanism as the
    #     exec fix above. Without sway's bin/ on PATH the bar block
    #     never spawns and only swaybg is visible.
    path = with pkgs; [
      dbus
      foot
      swaybg
      swaylock
      bashInteractive
      fuzzel
      git
      coreutils
      sway
    ];

    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
      ExecStart = "${pkgs.sway}/bin/sway -c /etc/sway/config";
      Restart = "on-failure";
      RestartSec = 3;
      StandardOutput = "journal";
      StandardError = "journal";
    };
    environment = {
      # Session-owned defaults for graphical apps launched via swaymsg exec.
      # Cemu's launcher should not have to manufacture Wayland/audio/XDG
      # basics; those belong to the Layer 14 guest session.
      XDG_RUNTIME_DIR = "/run/user/0";
      # WAYLAND_DISPLAY intentionally NOT pre-set here. Sway exports its
      # own WAYLAND_DISPLAY into the systemd activation environment when
      # the compositor finishes initializing, which is what clients
      # spawned via `swaymsg exec` / `bindsym ... exec` inherit. If we
      # pre-set it on the unit, wlroots reads the same variable at
      # startup, decides a parent Wayland socket exists, and selects its
      # nested *Wayland* backend instead of DRM. Sway then dies with
      # "backend/wayland/backend.c:608 Could not connect to remote
      # display: No such file or directory". Verified live on Thor
      # 2026-05-11 after cold boot.
      DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
      XDG_CURRENT_DESKTOP = "sway";
      SDL_AUDIODRIVER = "pulseaudio";
      HOME = "/storage";
      XDG_CONFIG_HOME = "/storage/.config";
      XDG_DATA_HOME = "/storage/.local/share";
      XDG_CACHE_HOME = "/storage/.cache";
      # Temporary Cemu compatibility root for existing ROCKNIX BIOS/keys/MLC
      # state. cemu-storage-adapter.sh consumes this; the package wrapper does
      # not know about ROCKNIX /storage paths.
      CEMU_BIOS_ROOT = "/storage/roms/bios/cemu";
      # Measured SM8550 Cemu affinity policy. Runtime A/B harnesses can set
      # CEMU_AFFINITY_MASK=none to test scheduler behavior explicitly.
      CEMU_AFFINITY_MASK = sm8550.performance.cemuAffinityMask;

      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_LIBINPUT_NO_DEVICES = "1";
      USER = "root";
    };
  };

  # Developer-shell packages baked in for parity with the former
  # dev-env profile. None of these are needed by sway itself; they
  # exist so the interactive Home-chord bindings below (Home then d for
  # fuzzel, etc.) and an interactive `foot` shell are useful out of the box.
  environment.systemPackages = with pkgs; [
    fuzzel
    git
    htop
    btop
  ];

  # Bake a device-aware sway config into /etc. The shared SM8550 defaults
  # remain the Thor-validated display and touch routing; Odin 2 Portal can
  # override only the measured device block without forking the kiosk policy.
  environment.etc."sway/config".text = ''
    # ROCKNIX Layer 14 sway config (${sm8550.deviceId} / SM8550).
    seat * hide_cursor 1000
    default_border none

    ${sm8550.display.swayDeviceConfig}

    # Prime the root user D-Bus activation environment once Sway has created
    # WAYLAND_DISPLAY/SWAYSOCK. Without this, GTK/wx apps can block for ~25s
    # while xdg-desktop-portal tries to start a backend with no display.
    exec_always ${portalBootstrap}

    # ---- Interactive bindings (combined main-space, 2026-05-11) ----

    # The AYN key is reserved for system/gamepad semantics. Home is a normal
    # keysym rather than a modifier, so use it as a transient chord prefix:
    # press Home, then the command key. Accept both common keysyms because the
    # handheld Home key can surface as either Home or XF86HomePage.
    set $home_chord_mode home-chord
    bindsym Home mode "$home_chord_mode"
    bindsym XF86HomePage mode "$home_chord_mode"

    mode "$home_chord_mode" {
      # Launch core apps
      bindsym Return exec foot, mode "default"
      bindsym d exec fuzzel, mode "default"
      bindsym g exec /storage/.guest/games-launcher.sh, mode "default"
      bindsym k exec korri-desktop-odin, mode "default"
      bindsym Shift+q kill, mode "default"
      bindsym Shift+e exec swaymsg exit, mode "default"

      # Reload config in place (useful for live tweaking)
      bindsym Shift+c reload, mode "default"

      # Focus
      bindsym Left  focus left, mode "default"
      bindsym Down  focus down, mode "default"
      bindsym Up    focus up, mode "default"
      bindsym Right focus right, mode "default"

      # Move window
      bindsym Shift+Left  move left, mode "default"
      bindsym Shift+Down  move down, mode "default"
      bindsym Shift+Up    move up, mode "default"
      bindsym Shift+Right move right, mode "default"

      # Layout
      bindsym f     fullscreen toggle, mode "default"
      bindsym space floating toggle, mode "default"
      bindsym s     layout stacking, mode "default"
      bindsym w     layout tabbed, mode "default"
      bindsym e     layout toggle split, mode "default"

      # Workspaces
      bindsym 1 workspace number 1, mode "default"
      bindsym 2 workspace number 2, mode "default"
      bindsym 3 workspace number 3, mode "default"
      bindsym 4 workspace number 4, mode "default"
      bindsym 5 workspace number 5, mode "default"
      bindsym 6 workspace number 6, mode "default"
      bindsym 7 workspace number 7, mode "default"
      bindsym 8 workspace number 8, mode "default"
      bindsym 9 workspace number 9, mode "default"

      bindsym Shift+1 move container to workspace number 1, mode "default"
      bindsym Shift+2 move container to workspace number 2, mode "default"
      bindsym Shift+3 move container to workspace number 3, mode "default"
      bindsym Shift+4 move container to workspace number 4, mode "default"
      bindsym Shift+5 move container to workspace number 5, mode "default"
      bindsym Shift+6 move container to workspace number 6, mode "default"
      bindsym Shift+7 move container to workspace number 7, mode "default"
      bindsym Shift+8 move container to workspace number 8, mode "default"
      bindsym Shift+9 move container to workspace number 9, mode "default"

      # Cancel / leave chord mode.
      bindsym Escape mode "default"
      bindsym Home mode "default"
      bindsym XF86HomePage mode "default"
    }

    # ---- Status bar ----
    #
    # status_command is a fixed absolute path to a writeShellScript
    # output (Nix-built, immutable) so sway's config parser doesn't
    # have to deal with shell quoting. The script writes one line
    # every 5 s -- swaybar reads stdin line-by-line and redraws on
    # each newline.
    bar {
      position bottom
      status_command ${swayBarStatus}
      colors {
        background #1a1a1a
        statusline #d4d4d4
        focused_workspace #4d8eff #4d8eff #ffffff
        active_workspace  #2a2a2a #2a2a2a #d4d4d4
        inactive_workspace #1a1a1a #1a1a1a #888888
      }
    }

    # ---- Auto-launch on session start ----
    #
    # One terminal so the user lands on something interactive instead
    # of an empty dark screen. They can close it with Home then Shift+Q.
    exec foot
  '';
}
