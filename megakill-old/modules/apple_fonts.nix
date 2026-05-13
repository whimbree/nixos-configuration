# https://gist.github.com/robbins/dccf1238e971973a6a963b04c486c099
{ lib, stdenv, fetchurl, unzip, p7zip }:

stdenv.mkDerivation rec {
  pname = "apple-fonts";
  version = "1";



  pro = fetchurl {
    # https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg
    url = "https://files.bspwr.com/web/client/pubshares/PTuXK5PRNf4SxY8dJgNQbf/browse?path=%2FSF-Pro.dmg";
    sha256 = "sha256-u7cLbIRELSNFUa2OW/ZAgIu6vbmK/8kXXqU97xphA+0=";
  };

  compact = fetchurl {
    # https://devimages-cdn.apple.com/design/resources/download/SF-Compact.dmg
    url = "https://files.bspwr.com/web/client/pubshares/PTuXK5PRNf4SxY8dJgNQbf/browse?path=%2FSF-Compact.dmg";
    sha256 = "sha256-mcMM/cbmOA5ykyIb74bid9vU6wyl8nVwkvkd+VlOdwo=";
  };

  mono = fetchurl {
    # https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg
    url = "https://files.bspwr.com/web/client/pubshares/PTuXK5PRNf4SxY8dJgNQbf/browse?path=%2FSF-Mono.dmg";
    sha256 = "sha256-bUoLeOOqzQb5E/ZCzq0cfbSvNO1IhW1xcaLgtV2aeUU=";
  };

  ny = fetchurl {
    # https://devimages-cdn.apple.com/design/resources/download/NY.dmg
    url = "https://files.bspwr.com/web/client/pubshares/PTuXK5PRNf4SxY8dJgNQbf/browse?path=%2FNY.dmg";
    sha256 = "sha256-HC7ttFJswPMm+Lfql49aQzdWR2osjFYHJTdgjtuI+PQ=";
  };

  nativeBuildInputs = [ p7zip ];

  sourceRoot = ".";

  dontUnpack = true;

  installPhase = ''
    7z x ${pro}
    cd SFProFonts 
    7z x 'SF Pro Fonts.pkg'
    7z x 'Payload~'
    mkdir -p $out/fontfiles
    mv Library/Fonts/* $out/fontfiles
    cd ..
    7z x ${mono}
    cd SFMonoFonts
    7z x 'SF Mono Fonts.pkg'
    7z x 'Payload~'
    mv Library/Fonts/* $out/fontfiles
    cd ..
    7z x ${compact}
    cd SFCompactFonts
    7z x 'SF Compact Fonts.pkg'
    7z x 'Payload~'
    mv Library/Fonts/* $out/fontfiles
    cd ..
    7z x ${ny}
    cd NYFonts
    7z x 'NY Fonts.pkg'
    7z x 'Payload~'
    mv Library/Fonts/* $out/fontfiles
    mkdir -p $out/usr/share/fonts/OTF $out/usr/share/fonts/TTF
    mv $out/fontfiles/*.otf $out/usr/share/fonts/OTF
    mv $out/fontfiles/*.ttf $out/usr/share/fonts/TTF
    rm -rf $out/fontfiles
  '';

  meta = {
    description = "Apple San Francisco, New York fonts";
    homepage = "https://developer.apple.com/fonts/";
    license = lib.licenses.unfree;
  };
}