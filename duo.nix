{ config, lib, pkgs, modulesPath, ... }:
let
  duo-buildroot-sdk = pkgs.fetchFromGitHub {
    owner = "milkv-duo";
    repo = "duo-buildroot-sdk";
    rev = "362832ac6632b4b6487d9a4046363371b62d727e"; # 2024-03-26
    hash = "sha256-G+NC6p4frv89HA42T/hHefAKEBnaNC6Ln/RKdyJ//M4=";
  };
  version = "5.10.4";
  src = "${duo-buildroot-sdk}/linux_${lib.versions.majorMinor version}";

  configfile = pkgs.writeText "milkv-duo-linux-config"
    (builtins.readFile ./prebuilt/duo-kernel-config.txt);

  netscript = pkgs.writeShellScriptBin "setup-network" ''
  #!/usr/bin/env bash
  sudo ip r add default via 192.168.4.1 dev usb0
  '';
    
  kernel = (pkgs.linuxManualConfig {
    inherit version src configfile;
    allowImportFromDerivation = true;
  }).overrideAttrs {
    preConfigure = ''
      substituteInPlace arch/riscv/Makefile \
        --replace '-mno-ldd' "" \
        --replace 'KBUILD_CFLAGS += -march=$(riscv-march-cflags-y)' \
                  'KBUILD_CFLAGS += -march=$(riscv-march-cflags-y)_zicsr_zifencei' \
        --replace 'KBUILD_AFLAGS += -march=$(riscv-march-aflags-y)' \
                  'KBUILD_AFLAGS += -march=$(riscv-march-aflags-y)_zicsr_zifencei'
    '';
  };
in
{

  disabledModules = [
    "profiles/all-hardware.nix"
  ];

  imports = [
    "${modulesPath}/installer/sd-card/sd-image.nix"
    ./channel.nix
  ];

  nixpkgs = {
    localSystem.config = "x86_64-unknown-linux-gnu";
    crossSystem.config = "riscv64-unknown-linux-gnu";
  };

  boot.kernelPackages = pkgs.linuxPackagesFor kernel;

  boot.kernelParams = [ "console=ttyS0,115200" "earlycon=sbi" "riscv.fwsz=0x80000" ];
  boot.consoleLogLevel = 9;

  boot.initrd.includeDefaultModules = false;
  boot.initrd.systemd = {
    # enable = true;
    # enableTpm2 = false;
  };

  boot.loader = {
    grub.enable = false;
  };

  boot.kernel.sysctl = {
    "vm.watermark_boost_factor" = 0;
    "vm.watermark_scale_factor" = 250; # increase swap aggression in kswapd. max is 30%, or 300.
    "vm.page-cluster" = 3; # increase swap pre-fetching. 0,1,2. logarithmic.
    "vm.swappiness" = 200;
    "kernel.pid_max" = 4096 * 8; # PAGE_SIZE * 8
    "vm.overcommit_memory" = 1; # 1 pretends we always have memory
    #"vm.overcommit_ratio" = 80; 
    "vm.vfs_cache_pressure" = 200; # reclaim cached dirs and inodes aggressively.
  };

  system.build.dtb = pkgs.runCommand "duo.dtb" { nativeBuildInputs = [ pkgs.dtc ]; } ''
    dtc -I dts -O dtb -o "$out" ${pkgs.writeText "duo.dts" ''
      /include/ "${./prebuilt/cv1800b_milkv_duo_sd.dts}"
      / {
        chosen {
          bootargs = "init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}";
        };
      };
    ''}
  '';

  system.build.its = pkgs.writeText "cv180x.its" ''
    /dts-v1/;

    / {
      description = "Various kernels, ramdisks and FDT blobs";
      #address-cells = <2>;

      images {
        kernel-1 {
          description = "kernel";
          type = "kernel";
          data = /incbin/("${config.boot.kernelPackages.kernel}/${config.system.boot.loader.kernelFile}");
          arch = "riscv";
          os = "linux";
          compression = "none";
          load = <0x00 0x80200000>;
          entry = <0x00 0x80200000>;
          hash-2 {
            algo = "crc32";
          };
        };

        ramdisk-1 {
          description = "ramdisk";
          type = "ramdisk";
          data = /incbin/("${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}");
          arch = "riscv";
          os = "linux";
          compression = "none";
          load = <00000000>;
          entry = <00000000>;
        };

        fdt-1 {
          description = "flat_dt";
          type = "flat_dt";
          data = /incbin/("${config.system.build.dtb}");
          arch = "riscv";
          compression = "none";
          hash-1 {
            algo = "sha256";
          };
        };
      };

      configurations {
        config-cv1800b_milkv_duo_sd {
          description = "boot cvitek system with board cv1800b_milkv_duo_sd";
          kernel = "kernel-1";
          ramdisk = "ramdisk-1";
          fdt = "fdt-1";
        };
      };
    };
  '';

  system.build.bootsd = pkgs.runCommand "boot.sd"
    {
      nativeBuildInputs = [ pkgs.ubootTools pkgs.dtc ];
    } ''
    mkimage -f ${config.system.build.its} "$out"
  '';

  services.zram-generator = {
    enable = true;
    settings.zram0 = {
      compression-algorithm = "zstd";
      zram-size = "ram * 2";
    };
  };

  users.users.root.initialHashedPassword = "";
  services.getty.autologinUser = "root";

  services.udev.enable = false;
  services.nscd.enable = false;
  #networking.firewall.enable = false;
  #networking.useDHCP = false;
  
  ########################## THIS WILL MAKE IT A PROPER NIXOS SYSTEM!
  ########################## BY DEFAULT IT IS FALSE
  nix.enable = true;

  system.nssModules = lib.mkForce [ ];


  networking = {
    interfaces.usb0 = {
      ipv4.addresses = [
        {
          address = "192.168.4.2";
          prefixLength = 24;
        }
      ];
    };
    # dnsmasq reads /etc/resolv.conf to find 8.8.8.8 and 1.1.1.1
    nameservers =  [ "127.0.0.1" "8.8.8.8" "1.1.1.1"];
    useDHCP = false;
    dhcpcd.enable = false;
    defaultGateway = "192.168.58.1";
    hostName = "nixos-duo";
    firewall.enable = false;
  };

  # configure usb0 as an RNDIS device
  systemd.tmpfiles.settings = {
    "10-cviusb" = {
      "/proc/cviusb/otg_role".w.argument = "device";
    };
  };

  services.dnsmasq.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # generating the host key takes a while
  systemd.services.sshd.serviceConfig ={
    TimeoutStartSec = 120;
  };

  environment.systemPackages = with pkgs; [
    pfetch (python311.withPackages(ps: with ps; [pip wheel setuptools])) usbutils inetutils iproute2 vim htop netscript ranger neofetch git gcc gnumake pkg-config
  ];

  programs.less.lessopen = null;

  sdImage = {
    firmwareSize = 64;
    populateRootCommands = "";
    populateFirmwareCommands = ''
      cp ${./prebuilt/fip.bin}         firmware/fip.bin
      cp ${config.system.build.bootsd} firmware/boot.sd
    '';
  };

  swapDevices = [ { device = "/swap"; size = 2048; } ];
}
