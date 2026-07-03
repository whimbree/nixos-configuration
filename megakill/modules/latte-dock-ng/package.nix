# Vendored from whimbree/latte-dock-ng (fork of the Plasma 6 latte-dock-ng
# revival), since it is not packaged in nixpkgs. Pinned to a specific commit;
# bump `rev`/`hash` together after pushing new commits to the fork.
{ lib, stdenv, fetchFromGitHub, cmake, wayland, kdePackages }:

stdenv.mkDerivation rec {
  pname = "latte-dock-ng";
  version = "1.2.21-unstable-2026-07-03";

  src = fetchFromGitHub {
    owner = "whimbree";
    repo = "latte-dock-ng";
    rev = "455f14c68721e3153e5b4c0ff7379d05ddc30031";
    hash = "sha256-RI2uRcCu/NDQHWQ1UIyGPwz4vjTFZ9g3mQl64019seA=";
  };

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
    kdePackages.qttools
  ];

  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.qtwayland

    kdePackages.libplasma
    kdePackages.plasma-activities
    kdePackages.plasma-activities-stats
    kdePackages.plasma-workspace
    kdePackages.kwayland
    kdePackages.plasma-wayland-protocols
    kdePackages.layer-shell-qt
    wayland

    kdePackages.karchive
    kdePackages.kcmutils
    kdePackages.kconfig
    kdePackages.kcoreaddons
    kdePackages.kcrash
    kdePackages.kdbusaddons
    kdePackages.kdeclarative
    kdePackages.kglobalaccel
    kdePackages.kguiaddons
    kdePackages.ki18n
    kdePackages.kiconthemes
    kdePackages.kio
    kdePackages.kirigami
    kdePackages.knewstuff
    kdePackages.knotifications
    kdePackages.kpackage
    kdePackages.ksvg
    kdePackages.kwindowsystem
    kdePackages.kxmlgui
  ];

  cmakeFlags = [ "-DVERSION=${version}" ];

  meta = {
    description = "Dock-style app launcher based on Plasma frameworks (KDE Plasma 6 fork)";
    homepage = "https://github.com/whimbree/latte-dock-ng";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "latte-dock-ng";
  };
}
