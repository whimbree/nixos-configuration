# https://gist.github.com/j-brn/716a03822d256bc5bf5d77b951c7915c
{ stdenv, lib, fetchFromGitHub, kernel, kmod, looking-glass-client, ... }:

stdenv.mkDerivation rec {
  pname = "kvmfr-${version}-${kernel.version}";
  version = "e658c2e";

  # src = looking-glass-client.src;
  src = fetchFromGitHub {
    owner = "gnif";
    repo = "LookingGlass";
    rev = version;
    sha256 = "sha256-0P53Ez6bN+ZlBqS5maUObayd4g2cFeA60bq0LeD6zZ8=";
  };
  sourceRoot = "source/module";
  hardeningDisable = [ "pic" "format" ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = [
    "KVER=${kernel.modDirVersion}"
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    install -D kvmfr.ko -t "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/misc/"
  '';

  meta = with lib; {
    description = "This kernel module implements a basic interface to the IVSHMEM device for LookingGlass";
    homepage = "https://github.com/gnif/LookingGlass";
    license = licenses.gpl2Only;
    maintainers = with maintainers; [ j-brn ];
    platforms = [ "x86_64-linux" ];
  };
}