{
  actool,
  stdenv,
  lib,
  nodejs_24,
  pnpm_11,
  node-gyp,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpmBuildHook,
  electron_43,
  python3,
  makeWrapper,
  callPackage,
  fetchFromGitHub,
  fetchurl,
  jq,
  makeDesktopItem,
  copyDesktopItems,
  xcodebuild,
  replaceVars,
  noto-fonts-color-emoji,
  nixosTests,

  # command line arguments which are always set e.g "--password-store=kwallet6"
  commandLineArgs ? "",

  withAppleEmojis ? false,
}:
assert lib.warnIf (commandLineArgs != "")
  "`commandLineArgs` has been deprecated and will be removed in the future. Consider creating a wrapper script or a desktop entry with your desired flags."
  true;
let
  nodejs = nodejs_24;
  # Signal Desktop 8.23 ships a pnpm@11 workspace (config in pnpm-workspace.yaml).
  pnpm = pnpm_11;
  electron = electron_43;

  libsignal-node = callPackage ./libsignal-node.nix { inherit nodejs; };
  # node-sqlcipher 4.x also pins pnpm@11.
  signal-sqlcipher = callPackage ./signal-sqlcipher.nix {
    inherit pnpm nodejs;
  };

  webrtc = callPackage ./webrtc.nix { };
  ringrtc = callPackage ./ringrtc.nix { inherit webrtc; };

  version = "8.23.0";

  src = fetchFromGitHub {
    owner = "signalapp";
    repo = "Signal-Desktop";
    tag = "v${version}";
    hash = "sha256-0atm92i3ekGeKu+lHvYXqqJ4Rr2SWeVKSjL3SeMpUIg=";
    # Emoji font files will be added in `postFetch` if `withAppleEmojis` is enabled. They
    # are fetched separately below.
    postFetch = ''
      rm $out/fonts/emoji.woff2
    '';
  };

  apple-emoji = fetchurl {
    url = "https://github.com/signalapp/Signal-Desktop/raw/refs/tags/v${version}/fonts/emoji.woff2";
    hash = "sha256-yGdx5GZVnsmYn+SI9/yAfGhRyzO5Q5Bd0bW9AQyVzv8=";
    meta.license = lib.licenses.unfree;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "signal-desktop";
  inherit src version;

  strictDeps = true;
  nativeBuildInputs = [
    actool
    node-gyp
    nodejs
    pnpmConfigHook
    pnpmBuildHook
    pnpm
    makeWrapper
    python3
    jq
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    xcodebuild
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    copyDesktopItems
  ];

  patches = [
    ./force-90-days-expiration.patch

    # Drop once https://github.com/NixOS/nixpkgs/pull/520553 and https://github.com/NixOS/nixpkgs/pull/525241 land.
    ./dont-assert-unicode-17-emoji.patch
  ]
  ++ lib.optional (!withAppleEmojis) (
    # Signal ships the Apple emoji set without a licence and upstream
    # does not seem terribly interested in fixing this; see:
    #
    # * <https://github.com/signalapp/Signal-Android/issues/5862>
    # * <https://whispersystems.discoursehosting.net/t/signal-is-likely-violating-apple-license-terms-by-using-apple-emoji-in-the-sticker-creator-and-android-and-desktop-apps/52883>
    #
    # We work around this by replacing it with the Noto Color Emoji
    # set, which is available under a FOSS licence and more likely to
    # be used on a NixOS machine anyway. The Apple emoji are removed
    # in `postFetch` to ensure that the build doesn’t cache the
    # unlicensed emoji files.
    replaceVars ./replace-apple-emoji-with-noto-emoji.patch {
      inherit noto-fonts-color-emoji;
    }
  );

  postPatch = ''
    # The spell checker dictionary URL interpolates the electron version,
    # however, the official website only provides dictionaries for electron
    # versions which they vendor into the binary releases. Since we unpin
    # electron to use the one from nixpkgs the URL may point to nonexistent
    # resource if the nixpkgs version is different. To fix this we hardcode
    # the electron version to the declared one here instead of interpolating
    # it at runtime.
    substituteInPlace app/updateDefaultSession.main.ts \
      --replace-fail "\''${process.versions.electron}" "`jq -r '.devDependencies.electron' < package.json`"

    # Disable auto-updater https://github.com/signalapp/Signal-Desktop/issues/7667
    substituteInPlace config/production.json \
      --replace-fail '"updatesEnabled": true' '"updatesEnabled": false'

    # Nix builds do not need upstream release hooks (notarization and
    # language-pack postprocessing), and they expect a different macOS
    # app layout than nixpkgs' Electron provides.
    substituteInPlace package.json \
      --replace-fail '"artifactBuildCompleted": "scripts/artifact-build-completed.mjs",' "" \
      --replace-fail '"afterSign": "scripts/after-sign.mjs",' "" \
      --replace-fail '"afterPack": "scripts/after-pack.mjs",' "" \
      --replace-fail '"sign": "scripts/sign-macos.mjs",' "" \
      --replace-fail '"afterAllArtifactBuild": "scripts/after-all-artifact-build.mjs",' ""

    # pnpm 11 defaults this to "prompt", which aborts script execution in the
    # non-interactive Nix sandbox ("cannot prompt for confirmation"). The deps
    # are already installed frozen/offline by pnpmConfigHook, so skip the check.
    substituteInPlace pnpm-workspace.yaml \
      --replace-fail 'verifyDepsBeforeRun: prompt' 'verifyDepsBeforeRun: false'
  ''
  + lib.optionalString withAppleEmojis ''
    cp ${apple-emoji} fonts/emoji.woff2
  '';

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      patches
      ;
    inherit pnpm;
    fetcherVersion = 4;
    hash = "sha256-Oy3KUS9qRW6CRoEtLsUvyQz5jdD1s2SngrrUfq6NJLg=";
  };

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    SIGNAL_ENV = "production";
    SOURCE_DATE_EPOCH = 1786642944;
  };

  preBuild = ''
    if [ "`jq -r '.engines.node' < package.json | cut -d. -f1`" != "${lib.versions.major nodejs.version}" ]
    then
      die "nodejs version mismatch"
    fi

    if [ "`jq -r '.devDependencies.electron' < package.json | cut -d. -f1`" != "${lib.versions.major electron.version}" ]
    then
      die "electron version mismatch"
    fi

    if [ "`jq -r '.dependencies."@signalapp/libsignal-client"' < package.json`" != "${libsignal-node.version}" ]
    then
      die "libsignal-client version mismatch"
    fi

    if [ "`jq -r '.dependencies."@signalapp/sqlcipher"' < package.json`" != "${signal-sqlcipher.version}" ]
    then
      die "signal-sqlcipher version mismatch"
    fi

    if [ "`jq -r '.dependencies."@signalapp/ringrtc"' < package.json`" != "${ringrtc.version}" ]
    then
      die "ringrtc version mismatch"
    fi

    install -D ${ringrtc}/lib/libringrtc${stdenv.hostPlatform.extensions.library} \
      node_modules/@signalapp/ringrtc/build/libringrtc.node

    substituteInPlace package.json \
      --replace-fail '"node_modules/@signalapp/ringrtc/build/''${platform}/*''${arch}*.node",' \
                     '"node_modules/@signalapp/ringrtc/build/libringrtc.node",'

    substituteInPlace node_modules/@signalapp/ringrtc/dist/ringrtc/Native.js \
      --replace-fail 'exports.default = require(`../../build/''${os.platform()}/libringrtc-''${process.arch}.node`);' \
                     'exports.default = require(`../../build/libringrtc.node`);'

    rm -r node_modules/@signalapp/libsignal-client/prebuilds
    cp -r ${libsignal-node}/lib node_modules/@signalapp/libsignal-client/prebuilds

    rm -r node_modules/@signalapp/sqlcipher
    cp -r ${signal-sqlcipher} node_modules/@signalapp/sqlcipher

    # fs-xattr is required at runtime by preload.wrapper.js,
    # but with npmRebuild disabled its native binding is missing.
    # Build it explicitly against Electron headers ahead of packaging.
    export npm_config_nodedir=${electron.headers}
    pushd node_modules/fs-xattr
    node-gyp rebuild
    popd
    test -f node_modules/fs-xattr/build/Release/xattr.node

    cp -r ${electron.dist} electron-dist
    chmod -R u+w electron-dist

    # The art (sticker) creator is a member of the root pnpm workspace, so its
    # dependencies are already installed by the top-level pnpm install. Build
    # its dist here (electron-builder bundles sticker-creator/dist).
    pnpm --filter signal-art-creator run build

    # @signalapp/windows-ucv is imported on all platforms, but its TypeScript
    # output is normally produced by its preinstall script. pnpmConfigHook runs
    # `pnpm install --ignore-scripts`, so build it explicitly. The Windows
    # native addon is only loaded when process.platform === "win32".
    pushd packages/windows-ucv
    pnpm run build
    popd
    test -f node_modules/@signalapp/windows-ucv/dist/index.js

    # @signalapp/types is required at runtime by preload.wrapper.js, but its
    # output is normally produced by the prepare script.
    pushd packages/types
    pnpm run build
    popd
    test -f node_modules/@signalapp/types/dist/index.std.cjs
  '';

  pnpmBuildScript = "generate";

  postBuild = ''
    pnpm exec electron-builder \
      ${
        if stdenv.hostPlatform.isDarwin then "--mac" else "--linux"
      } "dir:${stdenv.hostPlatform.node.arch}" \
      --config.extraMetadata.environment=$SIGNAL_ENV \
      -c.electronDist=electron-dist \
      -c.electronVersion=${electron.version} \
      -c.npmRebuild=false \
      ${lib.optionalString stdenv.hostPlatform.isDarwin "-c.mac.identity=null"}
  '';

  installPhase = ''
    runHook preInstall
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    mkdir -p $out/{Applications,bin}
    cp -r dist/mac*/Signal.app $out/Applications
    makeWrapper "$out/Applications/Signal.app/Contents/MacOS/Signal" "$out/bin/signal-desktop" \
      --add-flags ${lib.escapeShellArg commandLineArgs}
  ''
  + lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
    mkdir -p $out/share/polkit-1/actions
    cp -r dist/*-unpacked/resources $out/share/signal-desktop
    mv $out/share/signal-desktop/*.policy $out/share/polkit-1/actions/

    for icon in build/icons/png/*
    do
      install -Dm644 $icon $out/share/icons/hicolor/`basename ''${icon%.png}`/apps/signal-desktop.png
    done

    makeWrapper '${lib.getExe electron}' "$out/bin/signal-desktop" \
      --add-flags "$out/share/signal-desktop/app.asar" \
      --set-default ELECTRON_FORCE_IS_PACKAGED 1 \
      --add-flags ${lib.escapeShellArg commandLineArgs}
  ''
  + ''
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "signal";
      desktopName = "Signal";
      exec = "${finalAttrs.meta.mainProgram} %U";
      type = "Application";
      terminal = false;
      icon = "signal-desktop";
      comment = "Private messaging from your desktop";
      startupWMClass = "signal";
      mimeTypes = [
        "x-scheme-handler/sgnl"
        "x-scheme-handler/signalcaptcha"
      ];
      categories = [
        "Network"
        "InstantMessaging"
        "Chat"
      ];
    })
  ];

  passthru = {
    inherit
      apple-emoji
      libsignal-node
      ringrtc
      webrtc
      signal-sqlcipher
      ;
    tests.application-launch = nixosTests.signal-desktop;
    updateScript.command = [ ./update.sh ];
  };

  meta = {
    description = "Private, simple, and secure messenger";
    longDescription = ''
      Signal Desktop is an Electron application that links with your
      "Signal Android" or "Signal iOS" app.
    '';
    homepage = "https://signal.org/";
    changelog = "https://github.com/signalapp/Signal-Desktop/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      agpl3Only

      # Various npm packages
      free
    ];
    maintainers = with lib.maintainers; [
      eclairevoyant
      iamanaws
      marcin-serwin
      teutat3s
    ];
    mainProgram = "signal-desktop";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
})
