# Product-agnostic power-state substrate verb + request watcher.
#
# Ownership flip (2026-06-10, validated live on Bandai / AYN Thor):
#
#   The previous modules/lid.nix owned the entire "fake suspend" pipeline
#   AND the hardware-button reading AND product-session policy (sway DPMS,
#   freezing the kiosk cgroup, stopping audio units). That coupled the
#   substrate to one product's session topology: it hard-coded uid-0 sway
#   sockets, `korri-kiosk.service` cgroup paths, and `main-space-pipewire*`
#   units. After Korri's rootless-session refactor those targets moved, so
#   3 of the 4 actions silently no-oped and the device "did nothing" on a
#   power press.
#
#   This module shrinks the substrate to a single product-agnostic root
#   verb plus a request watcher. It owns ONLY the battery knobs that are
#   genuinely substrate-level and the same on every product:
#
#     - cpufreq governors (policy*/scaling_governor)
#     - Wi-Fi radio (nmcli) + NetworkManager connection recovery
#     - Bluetooth radio (rfkill)
#
#   It does NOT touch the compositor, user-session scopes, or audio. Those
#   are product/session policy: the product reads its own button, blanks
#   its own screen, freezes its own session scopes, and then asks the
#   substrate to enter/exit the low-power radio state by dropping a request
#   marker. The substrate never references product units, sockets, or uids.
#
# Contract the substrate exposes to a product:
#
#     rocknix-powerstate enter   # snapshot (first-wins) + governors
#                                 # powersave + bt off + wifi off LAST
#     rocknix-powerstate exit    # restore governors/bt + wifi on, then
#                                 # `nmcli con up <snapshot>` if DHCP stalls,
#                                 # then consume the snapshot
#
#   Products usually do not invoke the verb directly. They drop a marker
#   into the request directory (default /run/rocknix-power/requests):
#
#     touch <requestDir>/enter.request   # ask the substrate to enter
#     touch <requestDir>/exit.request    # ask the substrate to exit
#
#   The watcher polls that directory once a second and runs the verb. The
#   directory is group-writable by `rocknix.power.requestGroup` so a
#   rootless product session can request transitions without root/polkit.
#
# Hard-won lessons baked in (all from on-device prototyping):
#
#   - First-wins snapshot + consume-on-exit are MANDATORY. A duplicate
#     `enter` arriving after Wi-Fi is already down must not overwrite the
#     captured `wifi.state=enabled` with `disabled`, or `exit` skips
#     radio-on entirely and the device is "dead until reboot". The verb
#     guards the snapshot behind an `active` marker and only re-applies
#     the (idempotent) low-power actions on a repeat enter.
#   - Do NOT use systemd path units for the request channel. PathExists
#     multi-triggers per request and trips unit-start-limit-hit, which
#     permanently kills the watcher. A boring 1s poll loop is correct.
#   - The NetworkManager radio can hang in "connecting (getting IP
#     configuration)" after a radio cycle; an explicit `nmcli con up
#     <profile>` recovers in ~1s. The fallback must stay.
#   - Button debounce (autorepeat) is the product's concern, not the
#     substrate's; the verb is idempotent and the watcher consumes markers.
#
# Kept from the old module:
#   - The host-reachable kill switch. /storage/.guest is the one path
#     bind-mounted RW across the host/guest boundary, so a host SSH session
#     can disable the whole pipeline even when the guest is unreachable:
#       ssh root@<host> 'touch /storage/.guest/lid-suspend.disabled'
#   - logind staying out of the way (HandleLidSwitch/HandlePowerKey ignore).
#     In an nspawn, real PM_SUSPEND is unsupported; logind escalation on a
#     lid/power edge previously took the container down.
{ config, lib, pkgs, ... }:

let
  cfg = config.rocknix.power;

  runtimeDir = cfg.runtimeDir;
  requestDir = "${runtimeDir}/requests";
  stateDir = "${runtimeDir}/state";
  killSwitch = cfg.killSwitch;

  powerstatePath = lib.makeBinPath (with pkgs; [
    coreutils
    gnugrep
    gnused
    networkmanager
    util-linux # rfkill
  ]);

  # rocknix-powerstate enter|exit -- the substrate's single power verb.
  powerstate = pkgs.writeShellScript "rocknix-powerstate" ''
    set -u
    export PATH=${powerstatePath}

    state_dir="${stateDir}"
    kill_switch="${killSwitch}"
    active_marker="$state_dir/active"
    log="$state_dir/powerstate.log"

    logline() {
      mkdir -p "$state_dir" 2>/dev/null || true
      echo "$(date -Is) powerstate: $*" >> "$log" 2>/dev/null || true
    }

    rfkill_bin() {
      if [ -x /run/wrappers/bin/rfkill ]; then
        /run/wrappers/bin/rfkill "$@"
      else
        rfkill "$@"
      fi
    }

    if [ -e "$kill_switch" ]; then
      logline "kill switch present ($kill_switch); skipping ''${1:-?}"
      exit 0
    fi

    enter() {
      # ---- first-wins snapshot (guarded by the active marker) ----
      if [ ! -e "$active_marker" ]; then
        mkdir -p "$state_dir"
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
          [ -d "$p" ] || continue
          cp "$p/scaling_governor" "$state_dir/$(basename "$p").governor" 2>/dev/null || true
        done
        nmcli -t -f WIFI radio 2>/dev/null | head -1 > "$state_dir/wifi.state" || true
        # Active wireless connection name, for the DHCP-stall recovery on exit.
        nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
          | grep ':802-11-wireless$' | head -1 | sed 's/:802-11-wireless$//' \
          > "$state_dir/wifi.profile" || true
        rfkill_bin list bluetooth 2>/dev/null > "$state_dir/bt.state" || true
        : > "$active_marker"
        logline "enter: snapshot captured"
      else
        logline "enter: snapshot already active; re-applying low-power state only"
      fi

      # ---- apply low-power state (idempotent) ----
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$p" ] || continue
        [ -w "$p/scaling_governor" ] || continue
        echo powersave > "$p/scaling_governor" 2>/dev/null || true
      done
      rfkill_bin block bluetooth 2>/dev/null || true
      # Wi-Fi LAST: this drops any active SSH/LAN session by design.
      nmcli radio wifi off 2>/dev/null || true
      logline "enter: low-power state applied"
    }

    exit_resume() {
      if [ ! -e "$active_marker" ]; then
        logline "exit: no active snapshot; nothing to restore"
        exit 0
      fi

      # ---- restore governors ----
      for f in "$state_dir"/policy*.governor; do
        [ -f "$f" ] || continue
        gov=$(cat "$f" 2>/dev/null || true)
        pol=$(basename "$f" .governor)
        target="/sys/devices/system/cpu/cpufreq/$pol/scaling_governor"
        [ -n "$gov" ] || continue
        [ -w "$target" ] || continue
        echo "$gov" > "$target" 2>/dev/null || true
      done

      # ---- restore bluetooth (only if it was unblocked before) ----
      if [ -f "$state_dir/bt.state" ] && \
          ! grep -q 'Soft blocked: yes' "$state_dir/bt.state"; then
        rfkill_bin unblock bluetooth 2>/dev/null || true
      fi

      # ---- restore Wi-Fi (only if it was enabled before) ----
      if [ -f "$state_dir/wifi.state" ] && grep -q enabled "$state_dir/wifi.state"; then
        nmcli radio wifi on 2>/dev/null || true

        # Wait up to 14s for a wifi-type device to reach "connected". The
        # radio can reassociate but stall indefinitely in "getting IP
        # configuration"; if it does, `nmcli con up <profile>` forces it
        # through (~1s). Check the wifi DEVICE state, not `STATE general`:
        # externally-managed interfaces (tailscale0, lo) keep general state
        # at "connected (local only)" while the radio is fully down, which
        # `grep '^connected'` would falsely match (verified on Bandai
        # 2026-06-10).
        connected=no
        i=0
        while [ "$i" -lt 14 ]; do
          if nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -q ':wifi:connected$'; then
            connected=yes
            break
          fi
          sleep 1
          i=$((i + 1))
        done

        if [ "$connected" = no ] && [ -s "$state_dir/wifi.profile" ]; then
          profile=$(cat "$state_dir/wifi.profile")
          try=0
          while [ "$try" -lt 4 ]; do
            if nmcli con up "$profile" 2>/dev/null; then
              connected=yes
              break
            fi
            sleep 2
            try=$((try + 1))
          done
          logline "exit: DHCP-stall recovery con-up '$profile' connected=$connected"
        fi
        logline "exit: wifi restored connected=$connected"
      fi

      # ---- consume the snapshot (first-wins on the next enter) ----
      rm -f "$active_marker" \
            "$state_dir/wifi.state" \
            "$state_dir/wifi.profile" \
            "$state_dir/bt.state" \
            "$state_dir"/policy*.governor 2>/dev/null || true
      logline "exit: snapshot consumed"
    }

    case "''${1:-}" in
      enter) enter ;;
      exit)  exit_resume ;;
      *)
        echo "rocknix-powerstate: usage: $0 enter|exit" >&2
        exit 64
        ;;
    esac
  '';

  # Long-running request watcher. Polls the request directory and runs the
  # verb. A boring poll loop on purpose -- see the path-unit lesson above.
  watcher = pkgs.writeShellScript "rocknix-powerstate-watcher" ''
    set -u
    export PATH=${lib.makeBinPath (with pkgs; [ coreutils ])}

    request_dir="${requestDir}"
    interval="${toString cfg.pollIntervalSeconds}"

    mkdir -p "$request_dir" 2>/dev/null || true

    while true; do
      # Process enter before exit within a tick so a press/press pair
      # settles on "resumed" rather than a stuck low-power state.
      if [ -e "$request_dir/enter.request" ]; then
        rm -f "$request_dir/enter.request" 2>/dev/null || true
        ${powerstate} enter || true
      fi
      if [ -e "$request_dir/exit.request" ]; then
        rm -f "$request_dir/exit.request" 2>/dev/null || true
        ${powerstate} exit || true
      fi
      sleep "$interval"
    done
  '';

  # Optional cheap self-heal: if Wi-Fi is down for longer than
  # `downSeconds` while no power-state snapshot is active, nudge it back.
  # This is insurance against the NM DHCP stall happening outside a
  # suspend/resume cycle. Default off.
  wifiWatchdog = pkgs.writeShellScript "rocknix-powerstate-wifi-watchdog" ''
    set -u
    export PATH=${powerstatePath}

    state_dir="${stateDir}"
    marker="${runtimeDir}/wlan0-down-since"
    down_seconds="${toString cfg.wifiWatchdog.downSeconds}"

    # Never fight an in-progress fake-suspend.
    if [ -e "$state_dir/active" ]; then
      rm -f "$marker" 2>/dev/null || true
      exit 0
    fi

    # Wifi DEVICE state, not `STATE general`: externally-managed interfaces
    # (tailscale0) keep general state at "connected (local only)" while the
    # radio is fully down, which would render this watchdog inert.
    if nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -q ':wifi:connected$'; then
      rm -f "$marker" 2>/dev/null || true
      exit 0
    fi

    now=$(date +%s)
    if [ ! -f "$marker" ]; then
      echo "$now" > "$marker"
      exit 0
    fi

    since=$(cat "$marker" 2>/dev/null || echo "$now")
    if [ $((now - since)) -lt "$down_seconds" ]; then
      exit 0
    fi

    # Down long enough: try to bring the last-known wireless profile up,
    # falling back to a plain radio toggle.
    profile=""
    [ -s "$state_dir/wifi.profile" ] && profile=$(cat "$state_dir/wifi.profile")
    if [ -n "$profile" ] && nmcli con up "$profile" 2>/dev/null; then
      rm -f "$marker" 2>/dev/null || true
      exit 0
    fi
    nmcli radio wifi on 2>/dev/null || true
    rm -f "$marker" 2>/dev/null || true
  '';
in
{
  options.rocknix.power = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the product-agnostic `rocknix-powerstate` verb and the
        request watcher. The watcher idles harmlessly until a product
        drops a request marker, so it is safe to leave enabled even on
        profiles with no product session.
      '';
    };

    runtimeDir = lib.mkOption {
      type = lib.types.str;
      default = "/run/rocknix-power";
      description = ''
        Base runtime directory. The request channel lives at
        `<runtimeDir>/requests` and the snapshot state at
        `<runtimeDir>/state`.
      '';
    };

    requestGroup = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "korri";
      description = ''
        When set, the request directory is group-owned by this group and
        group-writable (0775), so a rootless product session running as a
        member of the group can request enter/exit transitions without
        root or polkit. When null the request directory is root-only
        (0755) and only root can drop markers.
      '';
    };

    killSwitch = lib.mkOption {
      type = lib.types.str;
      default = "/storage/.guest/lid-suspend.disabled";
      description = ''
        Path whose existence disables the power verb entirely. Lives under
        /storage/.guest, the one path bind-mounted RW across the
        host/guest boundary, so it is reachable from a host SSH session
        even when the guest session is wedged.
      '';
    };

    pollIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Request-watcher poll interval in seconds.";
    };

    wifiWatchdog = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run a periodic Wi-Fi self-heal that nudges NetworkManager back
          up if it stays disconnected longer than `downSeconds` while no
          power-state snapshot is active. Insurance against the NM DHCP
          stall outside a suspend/resume cycle.
        '';
      };

      downSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = "How long Wi-Fi must stay down before the watchdog acts.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "rocknix-powerstate" ''exec ${powerstate} "$@"'')
    ];

    # Request channel + snapshot state. Created via tmpfiles so the
    # group-writable grant is declarative rather than an ExecStartPre.
    systemd.tmpfiles.rules =
      [
        "d ${runtimeDir} 0755 root root -"
        "d ${stateDir} 0700 root root -"
      ]
      ++ (
        if cfg.requestGroup == null
        then [ "d ${requestDir} 0755 root root -" ]
        else [ "d ${requestDir} 0775 root ${cfg.requestGroup} -" ]
      );

    systemd.services.rocknix-powerstate-watcher = {
      description = "ROCKNIX power-state request watcher (enter/exit radios + governors)";
      wantedBy = [ "multi-user.target" ];
      # Needs sysfs cpufreq writes, nmcli, rfkill, and /run state. No
      # sandboxing -- the watcher logic lives in a script file, not a unit
      # one-liner, so systemd never expands $vars in ExecStart.
      serviceConfig = {
        Type = "simple";
        ExecStart = "${watcher}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.rocknix-powerstate-wifi-watchdog = lib.mkIf cfg.wifiWatchdog.enable {
      description = "ROCKNIX Wi-Fi self-heal (recover NM DHCP stalls outside suspend)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${wifiWatchdog}";
      };
    };

    systemd.timers.rocknix-powerstate-wifi-watchdog = lib.mkIf cfg.wifiWatchdog.enable {
      description = "Periodic ROCKNIX Wi-Fi self-heal";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "1min";
        AccuracySec = "20s";
      };
    };

    # logind must stay out of the way. Real PM_SUSPEND is unsupported in
    # the nspawn (ROCKNIX 030-suspend_mode quirk disables it), and logind
    # escalation on a lid/power edge previously took the container down.
    # Power/lid semantics are owned by the product (which reads the button
    # and drives this verb), never by logind.
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandlePowerKey = "ignore";
      HandleSuspendKey = "ignore";
    };
  };
}
