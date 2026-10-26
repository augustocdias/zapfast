self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.zapfast;
  json = pkgs.formats.json { };
  # paths.rs: ProjectDirs::from("me", "paolino", "zapfast").
  configDir =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "${config.home.homeDirectory}/Library/Application Support/me.paolino.zapfast"
    else
      "${config.xdg.configHome}/zapfast";
  declared = json.generate "zapfast-settings.json" cfg.settings;
in
{
  options.programs.zapfast = {
    enable = lib.mkEnableOption "ZapFast, a native WhatsApp client";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "zapfast.packages.\${pkgs.stdenv.hostPlatform.system}.default";
      description = "The ZapFast package to install.";
    };

    settings = lib.mkOption {
      inherit (json) type;
      default = { };
      example = lib.literalExpression ''
        {
          check_for_updates = false;
          message_sound = "none";
          theme = "dark";
        }
      '';
      description = ''
        Keys merged into ZapFast's `settings.json` on every activation. Keys
        left out keep whatever the app last saved, so window geometry, recent
        emoji and the lock verifiers survive. A key declared here is reset on
        the next activation if it is changed in the app. Restart ZapFast after
        activation: it reads the file at start, and its next save writes back
        the values it holds in memory.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # settings.json cannot be a store symlink: the app replaces it whole on
    # every change and keeps its own state in it.
    home.activation.zapfastSettings = lib.mkIf (cfg.settings != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        zapfastDir=${lib.escapeShellArg configDir}
        zapfastFile="$zapfastDir/settings.json"
        run mkdir -p -m 700 "$zapfastDir"
        if [[ ! -e "$zapfastFile" ]]; then
          # A file without a version is migrated as one from older releases,
          # which would replace an explicit beige or black wallpaper.
          zapfastBase='{"version":1}'
        elif zapfastBase=$(${lib.getExe pkgs.jq} -c . "$zapfastFile" 2>/dev/null); then
          :
        else
          warnEcho "ZapFast: $zapfastFile is not valid JSON, leaving it unchanged"
          zapfastBase=
        fi
        if [[ -z "$zapfastBase" ]]; then
          :
        elif [[ -v DRY_RUN ]]; then
          echo "Would merge ${declared} into $zapfastFile"
        else
          zapfastTmp=$(mktemp "$zapfastDir/.settings.json.XXXXXX")
          ${lib.getExe pkgs.jq} -n --argjson base "$zapfastBase" \
            --slurpfile declared ${declared} '$base * $declared[0]' > "$zapfastTmp"
          chmod 600 "$zapfastTmp"
          mv "$zapfastTmp" "$zapfastFile"
        fi
        unset zapfastDir zapfastFile zapfastBase zapfastTmp
      ''
    );
  };
}
