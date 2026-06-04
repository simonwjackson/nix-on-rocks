{ pkgs, moonlightPackage }:

pkgs.runCommand "rocknix-moonlight-controllerdb-contract"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
  }
  ''
    set -eu

    db="${moonlightPackage}/share/moonlight/gamecontrollerdb.txt"
    thor_inputplumber_guid='030000005e0400008e02000001000000'

    test -f "$db" || {
      echo "Moonlight package missing controller DB: $db" >&2
      exit 1
    }

    line="$(grep "^$thor_inputplumber_guid,.*platform:Linux," "$db" || true)"
    test -n "$line" || {
      echo "Moonlight controller DB missing Thor/InputPlumber Linux Xbox 360 GUID: $thor_inputplumber_guid" >&2
      exit 1
    }

    case "$line" in
      *'dpdown:h0.4'*'dpleft:h0.8'*'dpright:h0.2'*'dpup:h0.1'*) : ;;
      *)
        echo "Moonlight controller DB maps Thor/InputPlumber D-pad incorrectly" >&2
        echo "$line" >&2
        exit 1
        ;;
    esac

    touch $out
  ''
