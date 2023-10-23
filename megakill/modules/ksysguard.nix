{ stdenv, fetchFromGitHub, lib, extra-cmake-modules, libsForQt5, libcap, libpcap
, lm_sensors, libnl }:

stdenv.mkDerivation (finalAttrs: {
  pname = "ksysguard";
  version = "2c18f3b";

  src = fetchFromGitHub {
    owner = "kde";
    repo = "ksysguard";
    rev = finalAttrs.version;
    hash = "sha256-PXiliA9Z4/xXvfrAJ5AU+z8c74tb7ccM/TphRWbG2/g=";
  };

  nativeBuildInputs =
    [ extra-cmake-modules libsForQt5.kdoctools libsForQt5.qt5.wrapQtAppsHook ];
  buildInputs = [
    libsForQt5.qt5.qtbase
    libsForQt5.kconfig
    libsForQt5.kcoreaddons
    libsForQt5.kitemviews
    libsForQt5.kinit
    libsForQt5.kiconthemes
    libsForQt5.knewstuff
    libsForQt5.libksysguard
    libsForQt5.ki18n
    libsForQt5.networkmanager-qt
    libcap
    libpcap
    lm_sensors
    libnl
  ];

  meta = with lib; {
    description = "Resource usage monitor for your computer ";
    longDescription = ''
      KSysGuard is a program to monitor various elements of your system, or any
      other remote system with the KSysGuard daemon (ksysgardd) installed. 
      Currently the daemon has been ported to Linux, FreeBSD, Irix, NetBSD,
      OpenBSD, Solaris and Tru64 with varying degrees of completion.
    '';
    homepage = "https://github.com/KDE/ksysguard";
    license = licenses.gpl3;
    maintainers = [ maintainers.whimbree ];
    platforms = [ "x86_64-linux" ];
  };
})