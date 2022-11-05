{ config, lib, pkgs, modulesPath, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    ./filesystem.nix
    ./persist.nix
    ./luks.nix
    ./nas.nix
    ./tailscale.nix
    ./cockpit.nix
    ./virtualisation.nix
    ./nextcloud.nix
    ./services.nix
  ];

  boot.initrd.availableKernelModules =
    [ "xhci_pci" "ahci" "nvme" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  networking.hostName = "bastion";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall = {
    enable = true;
    allowPing = true;
  };

  hardware.cpu.amd.updateMicrocode =
    lib.mkDefault config.hardware.enableRedistributableFirmware;

  services.openssh = {
    enable = true;
    permitRootLogin = "no";
    # require public key authentication for better security
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
  };

  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  users.mutableUsers = false;

  users.users.bree = {
    isNormalUser = true;
    home = "/home/bree";
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH60UIt7lVryCqJb1eUGv/2RKCeozHpjUIzpRJx9143B b.ermakovspektor@ufl.edu"
    ];
    initialHashedPassword =
      "$6$7VpgKuNZIEImsE3g$MdQdQz0ZhEB.RkPPtM/UpGXlKEAn09C39A5zRG43LuP7gUgVdXgkmglhUwX6gNREQuRZlaeG6qhjGbxGYyBjq/";
  };
  users.users.root.initialHashedPassword =
    "$6$7VpgKuNZIEImsE3g$MdQdQz0ZhEB.RkPPtM/UpGXlKEAn09C39A5zRG43LuP7gUgVdXgkmglhUwX6gNREQuRZlaeG6qhjGbxGYyBjq/";

  environment.systemPackages = with pkgs; [ firefox ];

  system.stateVersion = "22.05";

  nixpkgs.config.packageOverrides = pkgs: {
    nur = import (builtins.fetchTarball
      "https://github.com/nix-community/NUR/archive/master.tar.gz") {
        inherit pkgs;
      };
  };

  nixpkgs.config.allowUnfree = true;

}
