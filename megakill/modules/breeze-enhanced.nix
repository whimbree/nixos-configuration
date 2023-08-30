{ stdenv
, fetchFromGitHub
, cmake
, extra-cmake-modules
, libsForQt5
, kwin
, lib
}:

stdenv.mkDerivation rec {
  pname = "breeze-enhanced";
  version = "5.26";

  src = fetchFromGitHub {
    owner = "tsujan";
    repo = "BreezeEnhanced";
    rev = "V${version}";
    sha256 = "sha256-j0u5wzHHViAyAaNVHwhcEToO6bThK4oKpG0f8NQNxk4=";
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
    description = "A fork of KDE Breeze decoration with additional options ";
    homepage = "https://github.com/tsujan/BreezeEnhanced";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ whimbree ];
  };
}