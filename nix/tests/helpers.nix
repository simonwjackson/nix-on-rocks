{ pkgs }:

{
  runAssertions = name: assertions:
    let
      contract = builtins.toFile "${name}.json" (builtins.toJSON assertions);
    in
    pkgs.runCommand name { } ''
      cat ${contract} >/dev/null
      touch $out
    '';

  assertContract = prefix: condition: message:
    if condition then message else builtins.throw "${prefix} failed: ${message}";
}
