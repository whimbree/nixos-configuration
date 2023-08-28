{ lib, stdenv, pkgs, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "gpgfrontend";
  version = "v2.1.1";

  src = fetchFromGitHub {
    owner = "saturneric";
    repo = pname;
    rev = version;
    sha256 = "sha256-PYIKqbCz5snq/iGG9hwTRI0o0JAyjoZ/SylLEAgQmVQ=";
    fetchSubmodules = true;
  };

  nativeBuildInputs = with pkgs; [ cmake ninja qt6.wrapQtAppsHook coreutils ];
  buildInputs = with pkgs; [
    boost
    openssl
    qt6.qtbase
    qt6.qt5compat
    gpgme
    libconfig
    libarchive
  ];

  cmakeFlags = [ "-DCMAKE_SKIP_BUILD_RPATH=ON" ];

  postConfigure = ''
    substituteInPlace ../src/CMakeLists.txt \
      --replace "/bin/mkdir" "${pkgs.coreutils}/bin/mkdir"
    substituteInPlace ../src/CMakeLists.txt \
      --replace "/bin/mv" "${pkgs.coreutils}/bin/mv"
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp src/ui/libgpgfrontend_ui.so $out/lib/
    cp src/core/libgpgfrontend_core.so $out/lib/

    cp -r release/gpgfrontend/var/empty/bin $out/
    cp -r release/gpgfrontend/var/empty/share $out/
    cp -r release/gpgfrontend/usr/share/ $out/
  '';

  meta = with lib; {
    description = "GUI frontend for the modern GnuPG (gpg)";
    license = licenses.gpl3;
    maintainers = with maintainers; [ whimbree ];
    homepage = "https://github.com/saturneric/GpgFrontend";
    inherit version;
  };
}
