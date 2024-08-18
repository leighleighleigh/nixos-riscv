{ pkgs, stdenv, lib, fetchFromGitHub, kernel, kmod }:

stdenv.mkDerivation rec {
  name = "batman-adv-${version}-${kernel.version}";
  version = "2024.2";

  src = fetchFromGitHub {
    owner = "open-mesh-mirror";
    repo = "batman-adv";
    rev = "v${version}";
    sha256 = "sha256-0qcs0Cuq72u6yVa5aEtdMC9SpfiwN9HPC6szERT3TJI=";
  };

  #sourceRoot = "source/linux/v4l2loopback";
  hardeningDisable = [ "pic" "format" ];                                    # 1
  buildInputs = kernel.moduleBuildDependencies ++ [ pkgs.stdenv.cc.cc pkgs.gcc pkgs.pkg-config pkgs.gnumake ];

  makeFlags = [
    "KERNELRELEASE=${kernel.modDirVersion}"                                 # 3
    "KERNEL_DIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"    # 4
    "KERNELPATH=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"    # 4
    "INSTALL_MOD_PATH=$(out)"                                               # 5
  ];

  meta = with lib; {
    description = "batman-adv";
    homepage = "https://github.com/open-mesh-mirror/batman-adv";
    license = licenses.gpl2;
    maintainers = [];
    platforms = platforms.linux;
  };
}
