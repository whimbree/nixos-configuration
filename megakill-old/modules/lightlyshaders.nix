# https://discourse.nixos.org/t/trouble-packaging-lightlyshaders-for-plasma-kwin-effect/19336/2
{ lib, stdenv, fetchFromGitHub, cmake, extra-cmake-modules, systemsettings
, libsForQt5, libepoxy, pkgs }:

stdenv.mkDerivation rec {
  pname = "lightlyshaders";
  version = "git";

  src = fetchFromGitHub {
    owner = "a-parhom";
    repo = pname;
    rev = "cea07c0";
    sha256 = "sha256-l6UXgU2Xv57Ge9fO6tk5a6+mPG7zrxdm28FAOSRZnA4=";
  };

  #cmakeFlags = [ ];

  nativeBuildInputs = [ cmake extra-cmake-modules pkgs.qt5.wrapQtAppsHook ];

  buildInputs = [
    libsForQt5.kwindowsystem
    libsForQt5.plasma-framework
    systemsettings
    libsForQt5.kinit
    libsForQt5.kdecoration
    libsForQt5.kwin
    libepoxy
    libsForQt5.kdelibs4support
    libsForQt5.qt5.qtbase
  ];

  postConfigure = ''
    substituteInPlace cmake_install.cmake \
      --replace "${libsForQt5.kdelibs4support}" "$out"
  '';

  meta = with lib; {
    description =
      "This version has almost zero performance impact, as well as correctly works with stock Plasma effects";
    license = licenses.mit;
    maintainers = with maintainers; [ whimbree ];
    homepage = "https://github.com/a-parhom/LightlyShaders";
    inherit (libsForQt5.kwindowsystem.meta) platforms;
  };
}
