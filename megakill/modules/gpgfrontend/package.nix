{ lib
, stdenv
, fetchFromGitHub
, cmake
, ninja
, pkg-config
, qt6
, rustPlatform
, cargo
, rustc
, gpgme
, libgpg-error
, libassuan
, libsodium
, libarchive
, openssl
, gtest
, icu
, gnupg
, pinentry-qt
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gpgfrontend";
  version = "2.2.1";

  src = fetchFromGitHub {
    owner = "saturneric";
    repo = "GpgFrontend";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YK/NFbqsyzy1WKZoLfU1BL0rX+Wl8oBgNL3JkMMX51o=";
    # The Rust engine (corrosion), Qt translations and the module SDK are
    # pulled in as git submodules. gpgme/libassuan/libgpg-error submodules are
    # only consumed when statically linking GpgME, which we do not do (we use
    # the system libraries instead).
    fetchSubmodules = true;
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) src;
    cargoRoot = "rust";
    hash = "sha256-yFTcZgdmk/Jv1P+2wLZuvuZGX8lrXH6xWnGduWYDpK0=";
  };

  # The Rust rPGP engine lives in ./rust and is built via Corrosion during the
  # CMake build. cargoSetupHook configures Cargo to use the vendored deps.
  cargoRoot = "rust";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.wrapQtAppsHook
    qt6.qttools
    rustPlatform.cargoSetupHook
    cargo
    rustc
  ];

  buildInputs = [
    qt6.qtbase
    qt6.qt5compat
    gpgme
    libgpg-error
    libassuan
    libsodium
    libarchive
    openssl
    gtest
    # Charset handling for the vmime library used by the e-mail module.
    icu
  ];

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    # Build the integrated modules (GnuPG info, e-mail, key server sync,
    # version check).
    (lib.cmakeBool "GPGFRONTEND_BUILD_MODULES" true)
  ];

  # GnuPG is required at runtime by the default (GnuPG) engine. GpgFrontend also
  # probes $PATH for a graphical pinentry (pinentry-gnome3, pinentry-qt, ...);
  # on non-FHS systems these are not on $PATH, so bundle pinentry-qt to match
  # the Qt UI and let gpg-agent prompt for passphrases.
  qtWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ gnupg pinentry-qt ]}"
  ];

  meta = {
    description = "Cross-platform OpenPGP tool with GnuPG and Rust rPGP engines";
    longDescription = ''
      GpgFrontend is a free, open-source, robust yet user-friendly, compact and
      cross-platform tool for OpenPGP encryption. It features a dual-engine core,
      letting you switch between the battle-tested GnuPG backend and a modern,
      memory-safe Rust rPGP backend supporting OpenPGP v6 (RFC 9580) and
      post-quantum algorithms.
    '';
    homepage = "https://gpgfrontend.bktus.com";
    changelog = "https://github.com/saturneric/GpgFrontend/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Plus;
    maintainers = with lib.maintainers; [ whimbree ];
    mainProgram = "gpgfrontend";
    platforms = lib.platforms.linux;
  };
})
