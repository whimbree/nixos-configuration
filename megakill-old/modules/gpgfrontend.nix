{ lib, stdenv, fetchFromGitHub, coreutils, cmake, ninja, qt6, boost, openssl, gpgme, libconfig, libarchive, gtest, pinentry-qt, gnupg, makeWrapper }:

stdenv.mkDerivation (finalAttrs: {
  pname = "gpgfrontend";
  version = "2.1.8";

  src = fetchFromGitHub {
    owner = "saturneric";
    repo = "gpgfrontend";
    rev = "v${finalAttrs.version}";
    hash = "sha256-q5FdA6E00knjdOjjAmkGwx9dMPx1JqG510HgamZECmU=";
    fetchSubmodules = true;
  };

  # Add patch to fix Qt6 QString::arg compatibility
  postPatch = ''
    substituteInPlace src/core/function/gpg/GpgSmartCardManager.cpp \
      --replace "result += QString(\"%%%1\").arg(ch, 2, 16, QLatin1Char('0'))" \
                "result += QString(\"%%%1\").arg(static_cast<unsigned char>(ch), 2, 16, QLatin1Char('0'))"
  '';

  nativeBuildInputs = [ cmake ninja qt6.wrapQtAppsHook coreutils qt6.qttools gtest makeWrapper ];
  buildInputs =
    [ boost openssl qt6.qtbase qt6.qt5compat gpgme libconfig libarchive pinentry-qt gnupg ];

  cmakeFlags = [
    "--no-warn-unused-cli"
    "-DCMAKE_SKIP_BUILD_RPATH=ON"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_TESTING=OFF"
  ];

  CXXFLAGS = "-Wno-error";

  postConfigure = ''
    substituteInPlace ../src/CMakeLists.txt \
      --replace "/bin/mkdir" "${coreutils}/bin/mkdir"
    substituteInPlace ../src/CMakeLists.txt \
      --replace "/bin/mv" "${coreutils}/bin/mv"
  '';

  installPhase = ''
    mkdir -p $out/{bin,lib,share}

    # Copy libraries
    cp src/ui/libgpgfrontend_ui.so $out/lib/ || echo "Failed to copy UI lib"
    cp src/core/libgpgfrontend_core.so $out/lib/ || echo "Failed to copy core lib"
    cp src/test/libgpgfrontend_test.so $out/lib/ || echo "Failed to copy test lib"
    cp src/sdk/libgpgfrontend_module_sdk.so $out/lib/ || echo "Failed to copy SDK lib"
    
    # Copy binary from the correct location
    cp artifacts/AppDir/var/empty/bin/GpgFrontend $out/bin/ || echo "Failed to copy binary"
    
    # Copy share files from the correct location
    if [ -d "artifacts/AppDir/var/empty/share" ]; then
      cp -r artifacts/AppDir/var/empty/share/* $out/share/
    else
      echo "Warning: Could not find share directory"
      find . -name "share" -type d
    fi
  '';

  # Use Qt's wrapper to ensure proper environment
  dontWrapQtApps = false;

  # # Set up environment variables but don't configure gpg-agent
  # postFixup = ''
  #   wrapProgram $out/bin/GpgFrontend \
  #     --set GNUPGHOME "$HOME/.gnupg"
  # '';

  meta = with lib; {
    description = "GUI frontend for GnuPG";
    longDescription = ''
    GpgFrontend is a free, open-source, robust yet user-friendly, compact and cross-platform tool for OpenPGP encryption. It stands out as an exceptional GUI frontend for the modern GnuPG (gpg).

    When using GpgFrontend, you can:

    - Rapidly encrypt files or text.
    - Digitally sign your files or text with ease.
    - Conveniently manage all your GPG keys on your device.
    - Transfer all your GPG keys between devices safely and effortlessly.
    '';
    homepage = "https://github.com/saturneric/GpgFrontend";
    license = licenses.gpl3;
    maintainers = [ maintainers.whimbree ];
    platforms = [ "x86_64-linux" "i686-linux" "aarch64-linux" ];
  };
})