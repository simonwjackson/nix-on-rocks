# Layer 14 dev-env profile.
#
# Sibling of profiles/main-space.nix. Composes the same six modules
# (base, tools, ssh, display, audio, network) but lands the user in
# an interactive sway session instead of a kiosk:
#
#   - One foot terminal pre-spawned so the screen isn't empty
#   - fuzzel as the application launcher (Home then d)
#   - Standard sway chord bindings (Home then Return, Home then Shift+Q,
#     workspaces, etc.)
#   - Built-in swaybar with clock + battery (Thor's pmic-glink path)
#   - Developer packages baked in: foot, fuzzel, git, htop, btop
#
# Selectable as `nixosConfigurations.rocknix-guest-dev-env` from the
# guest flake. Live-swap procedure documented at:
#   projects/ROCKNIX/packages/tools/nix-integration/docs/layer14-dev-env-profile.md
#
# Sway exec mechanism (used by every keybind) requires bashInteractive
# on the unit's PATH so execlp("sh", ...) resolves -- same fix carried
# in main-space.nix. See its long PATH comment for context.
{ lib, pkgs, ... }:

let
  # Status line script for swaybar. Lives as a separate file rather
  # than inline in the bar block because sway's config parser strips
  # shell quoting from `status_command`, which silently mangles any
  # multi-token script. As an absolute path to a writeShellScript
  # output, it survives sway parsing untouched and runs under the same
  # bash that U1 added to the unit's PATH.
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
in

{
  imports = [
    ../modules/base.nix
    ../modules/tools.nix
    ../modules/ssh.nix
    ../modules/display.nix
    ../modules/audio.nix
    ../modules/network.nix
    ../modules/lid.nix
  ];

  # Distinct from main-space ("rocknix-nix") so machinectl/journal/etc.
  # show which profile is currently booted.
  networking.hostName = lib.mkForce "rocknix-nix-dev";

  # Carry main-space's tz + journald tuning -- both decisions are
  # Layer-14-substrate concerns, not profile-specific.
  time.timeZone = "America/New_York";
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';

  # Developer packages on top of what display.nix already provides
  # (foot, swaybg, swaylock, wl-clipboard, grim, slurp, mesa-demos,
  # vulkan-tools).
  environment.systemPackages = with pkgs; [
    fuzzel
    git
    htop
    btop
  ];

  # Same kiosk-service launcher pattern main-space uses: bare systemd
  # unit, wlroots libseat backend, no greetd/PAM. The ONLY differences
  # from main-space are:
  #   - PATH adds fuzzel + git so keybinds can launch them
  #   - /etc/sway/config (below) bakes interactive keybinds + swaybar
  systemd.services.rocknix-sway-kiosk = {
    description = "ROCKNIX Layer 14 sway dev-env session";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" "systemd-user-sessions.service" ];

    path = with pkgs; [
      dbus
      foot
      swaybg
      swaylock
      bashInteractive
      fuzzel
      git
      coreutils  # for `date` and `cat` in the swaybar status_command
      sway       # makes `swaybar` reachable -- sway forks swaybar via
                 # execlp("swaybar", ...), same PATH-lookup mechanism
                 # as the U1 exec fix. Without sway's bin/ on PATH the
                 # bar block never spawns and only swaybg is visible.
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
      XDG_RUNTIME_DIR = "/run/user/0";
      WLR_NO_HARDWARE_CURSORS = "1";
      WLR_LIBINPUT_NO_DEVICES = "1";
      HOME = "/root";
      USER = "root";
    };
  };

  # Interactive sway config baked into /etc.
  #
  # Outputs/touch block is copied verbatim from main-space.nix so both
  # profiles render identically on Thor (DSI-2 main panel held
  # landscape, DSI-1 disabled, all touch pinned to DSI-2 with after-
  # patch per-device rules as no-ops on unpatched kernels).
  #
  # Battery path is /sys/class/power_supply/battery/capacity on Thor
  # (Qualcomm pmic-glink). Verified live 2026-05-08. The wildcard
  # fallback covers any future device that exposes BAT0 etc.
  environment.etc."sway/config".text = ''
    # ROCKNIX Layer 14 dev-env sway config (Thor / SM8550).
    seat * hide_cursor 1000
    default_border none

    output DSI-2 transform 90
    output DSI-2 scale 2.0
    output DSI-2 pos 0 0
    output DSI-2 bg #1a1a1a solid_color
    output DSI-2 allow_tearing yes
    output DSI-2 max_render_time off

    # Thor's bottom panel: 1080x1240 native, same physical orientation
    # as DSI-2. transform 90 + scale 2.0 yields 620x540 logical,
    # stacked under DSI-2's 960x540 starting at y=540.
    output DSI-1 enable
    output DSI-1 transform 90
    output DSI-1 scale 2.0
    output DSI-1 pos 0 540
    output DSI-1 bg #1a1a1a solid_color

    # Touch routing -- copied verbatim from main-space.nix. See its
    # comment block for the full kernel-patch / DT-input-name story.
    input type:touch map_to_output DSI-2
    input "0:0:ft5x06-top"    map_to_output DSI-2
    input "0:0:ft5x06-bottom" map_to_output DSI-1

    # The panels are physically portrait and displayed with transform 90.
    # Rotate touch coordinates the same way or taps land offset/rotated from
    # the rendered surface. Validated live on Thor 2026-05-11.
    input "0:0:ft5x06-top"    calibration_matrix 0 -1 1 1 0 0
    input "0:0:ft5x06-bottom" calibration_matrix 0 -1 1 1 0 0

    # ---- Interactive bindings ----

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

    # NOTE: games-launcher.sh autostart was removed because the
    # current kernel build does not yet apply the
    # 0054-edt-ft5x06-honour-DT-input-name patch -- both touchscreens
    # report the same identifier 0:0:generic_ft5x06_(8d), so sway
    # cannot route bottom-panel taps to DSI-1 surfaces and the menu
    # never receives a usable touch event. The Home then g chord still works;
    # otherwise launch BOTW directly
    # via:
    #   /storage/.guest/host-tune.sh <profile>     # on host
    #   /storage/.guest/botw-guest.sh <profile>    # in guest
  '';
}
