{ stdenv
, fetchFromGitHub
, cmake
, extra-cmake-modules
, libsForQt5
, kwin
, lib
}:

stdenv.mkDerivation rec {
  pname = "sierra-breeze";
  version = "git";

  src = fetchFromGitHub {
    owner = "ishovkun";
    repo = "SierraBreeze";
    rev = "62b203f";
    sha256 = "sha256-N7PH9GLFoth5FacT2rbk8PPshk7Ha8EsUaJmoxTp15E=";
  };

  nativeBuildInputs = [ cmake extra-cmake-modules libsForQt5.qt5.wrapQtAppsHook ];
  buildInputs = [ kwin ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_PREFIX=$out"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_TESTING=OFF"
    "-DKDE_INSTALL_USE_QT_SYS_PATHS=ON"
  ];

  meta = with lib; {
    description = "OSX-like window decoration for KDE Plasma written in C++";
    homepage = "https://github.com/ishovkun/SierraBreeze";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ whimbree ];
  };
}